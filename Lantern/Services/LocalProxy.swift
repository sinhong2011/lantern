import Foundation
import Network

/// Minimal Host-based reverse proxy so `http://name.local` reaches local published ports.
final class LocalProxy: @unchecked Sendable {
    enum ProxyError: LocalizedError {
        case bindFailed(String)
        var errorDescription: String? {
            switch self {
            case .bindFailed(let message): return message
            }
        }
    }

    private let lock = NSLock()
    private var listener: NWListener?
    private var routes: [String: Int] = [:]
    private var port: UInt16 = 80
    /// Set only while the listener is actually ready. Used so reconcile can
    /// update routes without tearing down and rebinding (port 80 fails often).
    private var boundPort: UInt16?
    var onAccess: (@Sendable (AccessEvent) -> Void)?

    func updateRoutes(_ aliases: [ServiceAlias]) {
        var next: [String: Int] = [:]
        for alias in aliases where alias.enabled {
            next[alias.hostName.lowercased()] = alias.localPort
            next[alias.name.lowercased()] = alias.localPort
        }
        lock.lock()
        routes = next
        lock.unlock()
    }

    func start(port: UInt16) async throws {
        if isBound(to: port) { return }

        stop()
        self.port = port

        let listener = try NWListener(using: Self.tcpParameters(), on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class ResumeOnce: @unchecked Sendable {
                private let lock = NSLock()
                private var didResume = false
                private let continuation: CheckedContinuation<Void, Error>

                init(_ continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }

                func resume(throwing error: Error? = nil) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !didResume else { return }
                    didResume = true
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            let gate = ResumeOnce(continuation)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.setBoundPort(port)
                    gate.resume()
                case .failed(let error):
                    self?.setBoundPort(nil)
                    gate.resume(throwing: ProxyError.bindFailed(error.localizedDescription))
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    func stop() {
        lock.lock()
        let existing = listener
        listener = nil
        boundPort = nil
        lock.unlock()
        existing?.cancel()
    }

    private func isBound(to port: UInt16) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener != nil && boundPort == port
    }

    private func setBoundPort(_ port: UInt16?) {
        lock.lock()
        boundPort = port
        lock.unlock()
    }

    private func handle(_ connection: NWConnection) {
        let started = ConnectGate()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard started.markReady() else { return }
                self.receiveHeader(connection, buffer: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    private func receiveHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                _ = error
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.route(client: connection, initial: next)
            } else if next.count > 65_536 {
                connection.cancel()
            } else {
                self.receiveHeader(connection, buffer: next)
            }
        }
    }

    private func route(client: NWConnection, initial: Data) {
        let line = HTTPAccess.requestLine(from: initial)
        let remote = Self.clientAddress(of: client)

        guard let host = Self.host(from: initial)?.lowercased() else {
            emit(method: line.method, path: line.path, host: "", client: remote, localPort: nil, outcome: .missingHost)
            sendQuick(client, status: 400, body: "Missing Host header.")
            return
        }
        lock.lock()
        let localPort = routes[host] ?? routes[host.replacingOccurrences(of: ".local", with: "")]
        lock.unlock()

        guard let localPort else {
            emit(method: line.method, path: line.path, host: host, client: remote, localPort: nil, outcome: .unknownHost)
            sendQuick(client, status: 404, body: "Unknown host. Add an alias in Lantern.")
            return
        }

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(localPort))!)
        let upstream = NWConnection(to: endpoint, using: Self.tcpParameters())
        let rewriter = RequestStreamRewriter(localPort: localPort) { [weak self] header in
            guard let self else { return }
            let next = HTTPAccess.requestLine(from: header)
            let nextHost = Self.host(from: header)?.lowercased() ?? host
            self.emit(
                method: next.method,
                path: next.path,
                host: nextHost,
                client: remote,
                localPort: localPort,
                outcome: .forwarded
            )
        }
        let connect = ConnectGate()
        let fail: @Sendable () -> Void = { [weak self] in
            guard let self, connect.consumeFailure() else { return }
            self.emit(
                method: line.method,
                path: line.path,
                host: host,
                client: remote,
                localPort: localPort,
                outcome: .upstreamDown
            )
            self.sendQuick(client, status: 502, body: "Upstream is down.")
            upstream.cancel()
        }
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard connect.markReady() else { return }
                let first = rewriter.ingest(initial)
                if !first.isEmpty {
                    upstream.send(content: first, completion: .contentProcessed { _ in })
                }
                self.pipe(from: client, to: upstream, rewriter: rewriter)
                self.pipe(from: upstream, to: client, rewriter: nil)
            case .failed:
                fail()
            case .cancelled:
                if !connect.didReady {
                    fail()
                } else {
                    client.cancel()
                    upstream.cancel()
                }
            default:
                break
            }
        }
        upstream.start(queue: DispatchQueue.global(qos: .userInitiated))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: fail)
    }

    private func emit(
        method: String,
        path: String,
        host: String,
        client: String?,
        localPort: Int?,
        outcome: AccessEvent.Outcome
    ) {
        onAccess?(AccessEvent(
            method: method,
            path: path,
            host: host,
            client: client,
            localPort: localPort,
            outcome: outcome
        ))
    }

    private static func clientAddress(of connection: NWConnection) -> String? {
        guard let endpoint = connection.currentPath?.remoteEndpoint else { return nil }
        if case .hostPort(let host, _) = endpoint {
            return "\(host)"
        }
        return nil
    }

    private func pipe(from: NWConnection, to: NWConnection, rewriter: RequestStreamRewriter?) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if error != nil {
                to.cancel()
                from.cancel()
                return
            }
            if let data, !data.isEmpty {
                let outgoing = rewriter?.ingest(data) ?? data
                if !outgoing.isEmpty {
                    to.send(content: outgoing, completion: .contentProcessed { sendError in
                        if sendError != nil {
                            to.cancel()
                            from.cancel()
                        }
                    })
                }
            }
            if isComplete {
                to.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    to.cancel()
                })
                return
            }
            self.pipe(from: from, to: to, rewriter: rewriter)
        }
    }

    private static func tcpParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        return parameters
    }

    private func sendQuick(_ connection: NWConnection, status: Int, body: String) {
        let payload = Data(body.utf8)
        let reason = status == 404 ? "Not Found" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func host(from request: Data) -> String? {
        guard let text = String(data: request, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("host:") {
                var value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let colon = value.firstIndex(of: ":") {
                    value = String(value[..<colon])
                }
                return value
            }
        }
        return nil
    }

    /// Dev servers (Vite, webpack, etc.) reject unknown Host values and also
    /// honor keep-alive — so every request on the connection must look local,
    /// not just the first one.
    static func rewriteForUpstream(_ request: Data, localPort: Int) -> Data {
        let text = String(data: request, encoding: .utf8)
            ?? String(data: request, encoding: .ascii)
        guard let text else { return request }

        let parts = text.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return request }
        let body = parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : ""

        let upstreamHost = "localhost:\(localPort)"
        let upstreamOrigin = "http://\(upstreamHost)"
        var originalHost: String?

        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        var sawHost = false
        var rewrittenLines: [String] = []
        rewrittenLines.reserveCapacity(lines.count + 1)

        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("host:") {
                originalHost = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                rewrittenLines.append("Host: \(upstreamHost)")
                sawHost = true
            } else if lower.hasPrefix("origin:") {
                rewrittenLines.append("Origin: \(upstreamOrigin)")
            } else if lower.hasPrefix("referer:") {
                let value = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if let host = originalHost,
                   let next = rewriteURLString(value, fromHost: host, toOrigin: upstreamOrigin) {
                    rewrittenLines.append("Referer: \(next)")
                } else {
                    rewrittenLines.append(line)
                }
            } else if lower.hasPrefix("x-forwarded-host:")
                        || lower.hasPrefix("x-original-host:")
                        || lower.hasPrefix("forwarded:") {
                continue
            } else {
                rewrittenLines.append(line)
            }
        }

        if let host = originalHost {
            for i in rewrittenLines.indices where rewrittenLines[i].lowercased().hasPrefix("referer:") {
                let value = rewrittenLines[i].dropFirst(8).trimmingCharacters(in: .whitespaces)
                if let next = rewriteURLString(value, fromHost: host, toOrigin: upstreamOrigin) {
                    rewrittenLines[i] = "Referer: \(next)"
                }
            }
        }

        if !sawHost, !rewrittenLines.isEmpty {
            rewrittenLines.insert("Host: \(upstreamHost)", at: min(1, rewrittenLines.count))
        }

        var rebuilt = rewrittenLines.joined(separator: "\r\n")
        rebuilt += "\r\n\r\n"
        rebuilt += body
        return Data(rebuilt.utf8)
    }

    fileprivate static func contentLength(in http: Data) -> Int? {
        let text = String(data: http, encoding: .utf8)
            ?? String(data: http, encoding: .ascii)
        guard let text else { return 0 }
        let head = text.components(separatedBy: "\r\n\r\n").first ?? text
        for raw in head.split(separator: "\r\n") {
            let line = raw.lowercased()
            if line.hasPrefix("transfer-encoding:"), line.contains("chunked") {
                return nil
            }
            if line.hasPrefix("content-length:") {
                return Int(raw.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func rewriteURLString(_ value: String, fromHost: String, toOrigin: String) -> String? {
        let hostOnly = fromHost.split(separator: ":").first.map(String.init) ?? fromHost
        guard let url = URL(string: value), let urlHost = url.host else {
            return nil
        }
        guard urlHost.caseInsensitiveCompare(hostOnly) == .orderedSame
            || urlHost.caseInsensitiveCompare(fromHost) == .orderedSame else {
            return nil
        }
        var path = url.path
        if path.isEmpty { path = "/" }
        if let query = url.query { path += "?\(query)" }
        if let fragment = url.fragment { path += "#\(fragment)" }
        return toOrigin + path
    }
}

private final class ConnectGate: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var failed = false

    var didReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }

    @discardableResult
    func markReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !ready, !failed else { return false }
        ready = true
        return true
    }

    func consumeFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !ready, !failed else { return false }
        failed = true
        return true
    }
}

/// Rewrites Host/Origin on every HTTP/1.1 request in a keep-alive stream.
private final class RequestStreamRewriter: @unchecked Sendable {
    private let lock = NSLock()
    private let localPort: Int
    private let onRequest: (@Sendable (Data) -> Void)?
    private var buffer = Data()
    private var bodyRemaining: Int = 0
    private var passthrough = false

    init(localPort: Int, onRequest: (@Sendable (Data) -> Void)? = nil) {
        self.localPort = localPort
        self.onRequest = onRequest
    }

    func ingest(_ data: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }

        if passthrough {
            return data
        }

        buffer.append(data)
        var output = Data()

        while true {
            if bodyRemaining > 0 {
                let take = min(bodyRemaining, buffer.count)
                if take == 0 { break }
                output.append(buffer.prefix(take))
                buffer.removeSubrange(0..<take)
                bodyRemaining -= take
                continue
            }

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { break }
            let headerBlock = Data(buffer[..<headerEnd.upperBound])
            buffer.removeSubrange(..<headerEnd.upperBound)
            onRequest?(headerBlock)
            let rewritten = LocalProxy.rewriteForUpstream(headerBlock, localPort: localPort)
            output.append(rewritten)

            if HTTPAccess.isWebSocketUpgrade(headerBlock) {
                passthrough = true
                output.append(buffer)
                buffer.removeAll()
                break
            }

            if let length = LocalProxy.contentLength(in: rewritten) {
                bodyRemaining = length
            } else {
                // Chunked client body — pass the rest of this connection through.
                passthrough = true
                output.append(buffer)
                buffer.removeAll()
                break
            }
        }

        return output
    }
}
