import Testing
@testable import Lantern

struct ServiceAliasTests {
    @Test(arguments: [
        ("Web App", "web-app"),
        ("  API  ", "api"),
        ("Foo--Bar", "foo-bar"),
        ("--x--", "x"),
    ])
    func sanitizesNames(_ raw: String, expected: String) {
        #expect(ServiceAlias.sanitizedName(raw) == expected)
    }

    @Test func portlessPublicURLOmits80() {
        let alias = ServiceAlias(name: "web", localPort: 8080)
        #expect(alias.publicURL(lanIP: "10.0.0.1", proxyPort: 80, proxyEnabled: true) == "http://web.local")
        #expect(alias.publicURL(lanIP: "10.0.0.1", proxyPort: 8787, proxyEnabled: true) == "http://web.local:8787")
    }
}
