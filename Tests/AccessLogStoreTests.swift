import Foundation
import Testing
@testable import Lantern

@MainActor
struct AccessLogStoreTests {
    @Test func newestFirstAndCapsAt300() {
        let store = AccessLogStore()
        for index in 1...301 {
            store.recordActivity(.broadcastOn, "\(index)")
        }
        #expect(store.entries.count == 300)
        guard case .activity(let first) = store.entries.first else {
            Issue.record("expected activity at head")
            return
        }
        #expect(first.message == "301")
        guard case .activity(let last) = store.entries.last else {
            Issue.record("expected activity at tail")
            return
        }
        #expect(last.message == "2")
    }

    @Test func filtersByKindHostAndQuery() {
        let store = AccessLogStore()
        store.append(.access(AccessEvent(
            method: "GET",
            path: "/",
            host: "web.local",
            client: "10.0.0.2",
            localPort: 8080,
            outcome: .forwarded
        )))
        store.recordActivity(.serviceAdded, "Added web.local → localhost:8080", host: "web.local")
        store.recordActivity(.broadcastOn, "Broadcast on")

        #expect(store.filtered(kind: .access, host: nil, query: "").count == 1)
        #expect(store.filtered(kind: .activity, host: nil, query: "").count == 2)
        #expect(store.filtered(kind: .all, host: "web.local", query: "").count == 2)
        #expect(store.filtered(kind: .all, host: nil, query: "broadcast").count == 1)
    }

    @Test func recentHitsArePerAlias() {
        let store = AccessLogStore()
        let web = ServiceAlias(name: "web", localPort: 8080)
        store.append(.access(AccessEvent(
            method: "GET", path: "/a", host: "web.local", client: nil, localPort: 8080, outcome: .forwarded
        )))
        store.append(.access(AccessEvent(
            method: "GET", path: "/b", host: "api.local", client: nil, localPort: 3000, outcome: .unknownHost
        )))
        let recent = store.recent(for: web, limit: 3)
        #expect(recent.count == 1)
        #expect(recent[0].path == "/a")
    }

    @Test func clearEmptiesTheRing() {
        let store = AccessLogStore()
        store.recordActivity(.broadcastOff, "Broadcast off")
        store.clear()
        #expect(store.entries.isEmpty)
    }
}
