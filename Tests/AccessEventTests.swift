import Foundation
import Testing
@testable import Lantern

struct AccessEventTests {
    @Test func matchesAliasHostAndBareName() {
        let alias = ServiceAlias(name: "web", localPort: 8080)
        let local = AccessEvent(method: "GET", path: "/", host: "web.local", client: nil, localPort: 8080, outcome: .forwarded)
        let bare = AccessEvent(method: "GET", path: "/", host: "web", client: nil, localPort: 8080, outcome: .forwarded)
        let other = AccessEvent(method: "GET", path: "/", host: "api.local", client: nil, localPort: 3000, outcome: .forwarded)
        #expect(local.matches(alias: alias))
        #expect(bare.matches(alias: alias))
        #expect(other.matches(alias: alias) == false)
    }

    @Test func queryMatchesPathHostClientAndOutcome() {
        let event = AccessEvent(
            method: "GET",
            path: "/src/main.ts",
            host: "web.local",
            client: "192.168.1.23",
            localPort: 5173,
            outcome: .upstreamDown
        )
        #expect(event.matches(query: "main.ts"))
        #expect(event.matches(query: "192.168"))
        #expect(event.matches(query: "upstream"))
        #expect(event.matches(query: "nope") == false)
    }
}
