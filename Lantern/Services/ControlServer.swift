import Foundation
import Network

/// Loopback JSON API for scripts (Raycast optional later).
/// Default: http://127.0.0.1:19247
final class ControlServer: @unchecked Sendable {
    private var listener: NWListener?
    private let lock = NSLock()
    private weak var app: AppModel?

    @MainActor
    func attach(app: AppModel) {
        lock.lock()
        self.app = app
        lock.unlock()
    }

    func start(port: UInt16 = 19_247) {
        stop()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: DispatchQueue.global(qos: .utility))
        } catch {
            // Non-fatal
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .utility))
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                let request = HTTPRequest.parse(next)
                self.respond(connection, request: request)
            } else {
                self.receive(connection, buffer: next)
            }
        }
    }

    private func respond(_ connection: NWConnection, request: HTTPRequest) {
        Task { @MainActor in
            let payload: [String: Any]
            if let app = self.app {
                payload = app.handleControl(method: request.method, path: request.path, body: request.body)
            } else {
                payload = ["ok": false, "error": "engine offline"]
            }
            let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]))
                ?? Data(#"{"ok":false}"#.utf8)
            var response = Data()
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
            response.append(Data(header.utf8))
            response.append(data)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

struct HTTPRequest {
    var method: String
    var path: String
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest {
        let text = String(data: data, encoding: .utf8) ?? ""
        let parts = text.components(separatedBy: "\r\n\r\n")
        let head = parts.first ?? ""
        let body = parts.count > 1 ? Data(parts[1].utf8) : Data()
        let lines = head.split(separator: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        let method = requestLine.count > 0 ? String(requestLine[0]) : "GET"
        let path = requestLine.count > 1 ? String(requestLine[1]) : "/"
        return HTTPRequest(method: method, path: path, body: body)
    }
}
