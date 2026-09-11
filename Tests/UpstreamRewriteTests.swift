import Foundation
import Testing
@testable import Lantern

struct UpstreamRewriteTests {
    @Test func rewritesHostAndOrigin() {
        let raw = Data("GET / HTTP/1.1\r\nHost: web.local\r\nOrigin: http://web.local\r\n\r\n".utf8)
        let text = String(data: LocalProxy.rewriteForUpstream(raw, localPort: 5173), encoding: .utf8) ?? ""
        #expect(text.contains("Host: localhost:5173"))
        #expect(text.contains("Origin: http://localhost:5173"))
        #expect(text.contains("Host: web.local") == false)
    }

    @Test func dropsForwardedHeaders() {
        let raw = Data("GET / HTTP/1.1\r\nHost: api.local\r\nX-Forwarded-Host: api.local\r\n\r\n".utf8)
        let text = String(data: LocalProxy.rewriteForUpstream(raw, localPort: 3000), encoding: .utf8) ?? ""
        #expect(text.lowercased().contains("x-forwarded-host") == false)
        #expect(text.contains("Host: localhost:3000"))
    }

    @Test func startOnTheSamePortIsIdempotent() async throws {
        let proxy = LocalProxy()
        let port = UInt16.random(in: 19_300...19_399)
        try await proxy.start(port: port)
        try await proxy.start(port: port)
        proxy.stop()
    }
}

struct HTTPRequestTests {
    @Test func parsesTokenHeader() {
        let raw = Data("POST /broadcast HTTP/1.1\r\nX-Lantern-Token: abc123\r\n\r\n".utf8)
        let request = HTTPRequest.parse(raw)
        #expect(request.method == "POST")
        #expect(request.path == "/broadcast")
        #expect(request.header("X-Lantern-Token") == "abc123")
    }
}

@MainActor
struct AliasStoreTests {
    @Test func rejectsDuplicateNames() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lantern-alias-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AliasStore(fileURL: url)
        store.upsert(ServiceAlias(name: "web", localPort: 8080))
        #expect(store.hasName("web"))
        #expect(store.hasName("WEB"))
        #expect(store.hasName("api") == false)
    }

    @Test func migratesLegacyPort80To8787() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lantern-alias-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacy = """
        {"masterBroadcastEnabled":false,"proxyEnabled":true,"proxyPort":80,"aliases":[],"launchAtLogin":false}
        """
        try Data(legacy.utf8).write(to: url)
        let store = AliasStore(fileURL: url)
        #expect(store.proxyPort == 8787)
    }

    @Test func keepsExplicitPort80AfterMigration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lantern-alias-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let optedIn = """
        {"masterBroadcastEnabled":false,"proxyEnabled":true,"proxyPort":80,"aliases":[],"launchAtLogin":false,"schemaVersion":2}
        """
        try Data(optedIn.utf8).write(to: url)
        let store = AliasStore(fileURL: url)
        #expect(store.proxyPort == 80)
    }
}
