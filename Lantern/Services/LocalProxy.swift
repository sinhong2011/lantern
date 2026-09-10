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
        stop()
        self.port = port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
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
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume()
                case .failed(let error):
                    gate.resume(throwing: ProxyError.bindFailed(error.localizedDescription))
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        receiveHeader(connection, buffer: Data())
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
        guard let host = Self.host(from: initial)?.lowercased() else {
            sendQuick(client, status: 400, body: "Missing Host header.")
            return
        }
        lock.lock()
        let localPort = routes[host] ?? routes[host.replacingOccurrences(of: ".local", with: "")]
        lock.unlock()

        guard let localPort else {
            sendQuick(client, status: 404, body: "Unknown host. Add an alias in Lantern.")
            return
        }

        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(localPort))!)
        let upstream = NWConnection(to: endpoint, using: .tcp)
        upstream.start(queue: DispatchQueue.global(qos: .userInitiated))
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let rewritten = Self.rewriteForUpstream(initial, localPort: localPort)
                upstream.send(content: rewritten, completion: .contentProcessed { _ in })
                self.pipe(from: client, to: upstream)
                self.pipe(from: upstream, to: client)
            case .failed, .cancelled:
                client.cancel()
                upstream.cancel()
            default:
                break
            }
        }
    }

    private func pipe(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { _ in
                    self.pipe(from: from, to: to)
                })
            } else if isComplete || error != nil {
                to.cancel()
                from.cancel()
            } else {
                self.pipe(from: from, to: to)
            }
        }
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

    /// Dev servers (Vite, etc.) often block unknown Host values. Don't force every
    /// project to change config — present the request as localhost instead.
    private static func rewriteForUpstream(_ request: Data, localPort: Int) -> Data {
        guard let text = String(data: request, encoding: .utf8) else { return request }
        let parts = text.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first else { return request }
        let body = parts.count > 1 ? parts[1...].joined(separator: "\r\n\r\n") : ""

        let upstreamHost = "127.0.0.1:\(localPort)"
        let upstreamOrigin = "http://\(upstreamHost)"
        var originalHost: String?

        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        for i in lines.indices {
            let lower = lines[i].lowercased()
            if lower.hasPrefix("host:") {
                originalHost = lines[i].dropFirst(5).trimmingCharacters(in: .whitespaces)
                lines[i] = "Host: \(upstreamHost)"
            } else if lower.hasPrefix("origin:") {
                lines[i] = "Origin: \(upstreamOrigin)"
            } else if lower.hasPrefix("referer:") {
                let value = lines[i].dropFirst(8).trimmingCharacters(in: .whitespaces)
                if let host = originalHost ?? host(from: request),
                   let rewritten = rewriteURLString(value, fromHost: host, toOrigin: upstreamOrigin) {
                    lines[i] = "Referer: \(rewritten)"
                }
            }
        }

        // Second pass for Referer if Host appeared after it.
        if let host = originalHost {
            for i in lines.indices where lines[i].lowercased().hasPrefix("referer:") {
                let value = lines[i].dropFirst(8).trimmingCharacters(in: .whitespaces)
                if let rewritten = rewriteURLString(value, fromHost: host, toOrigin: upstreamOrigin) {
                    lines[i] = "Referer: \(rewritten)"
                }
            }
        }

        var rebuilt = lines.joined(separator: "\r\n")
        rebuilt += "\r\n\r\n"
        rebuilt += body
        return Data(rebuilt.utf8)
    }

    private static func rewriteURLString(_ value: String, fromHost: String, toOrigin: String) -> String? {
        let hostOnly = fromHost.split(separator: ":").first.map(String.init) ?? fromHost
        guard let url = URL(string: value), let urlHost = url.host else {
            // Relative or opaque — leave unchanged.
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
