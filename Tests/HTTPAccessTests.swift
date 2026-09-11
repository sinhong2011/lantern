import Foundation
import Testing
@testable import Lantern

struct HTTPAccessTests {
    @Test(arguments: [
        ("GET / HTTP/1.1\r\nHost: web.local\r\n\r\n", "GET", "/"),
        ("POST /api/save HTTP/1.1\r\n\r\n", "POST", "/api/save"),
        ("get /Vite?t=1 HTTP/1.1\r\n\r\n", "GET", "/Vite?t=1"),
        ("\r\n\r\n", "GET", "/"),
    ])
    func parsesRequestLine(_ raw: String, method: String, path: String) {
        let line = HTTPAccess.requestLine(from: Data(raw.utf8))
        #expect(line.method == method)
        #expect(line.path == path)
    }

    @Test func truncatesLongPaths() {
        let long = "/" + String(repeating: "a", count: 400)
        let raw = "GET \(long) HTTP/1.1\r\n\r\n"
        let line = HTTPAccess.requestLine(from: Data(raw.utf8))
        #expect(line.path.count == HTTPAccess.maxPathLength)
    }

    @Test func detectsWebSocketUpgrade() {
        let upgrade = Data("GET /ws HTTP/1.1\r\nUpgrade: websocket\r\n\r\n".utf8)
        let plain = Data("GET / HTTP/1.1\r\nHost: web.local\r\n\r\n".utf8)
        #expect(HTTPAccess.isWebSocketUpgrade(upgrade))
        #expect(HTTPAccess.isWebSocketUpgrade(plain) == false)
    }
}
