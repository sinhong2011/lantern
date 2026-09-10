import Foundation

struct ServiceAlias: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var localPort: Int
    var enabled: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        localPort: Int,
        enabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.name = Self.sanitizedName(name)
        self.localPort = localPort
        self.enabled = enabled
        self.notes = notes
    }

    var hostName: String { "\(name).local" }

    func publicURL(lanIP: String?, proxyPort: Int?, proxyEnabled: Bool) -> String {
        let host = hostName
        if proxyEnabled, let proxyPort {
            if proxyPort == 80 {
                return "http://\(host)"
            }
            return "http://\(host):\(proxyPort)"
        }
        return "http://\(host):\(localPort)"
    }

    static func sanitizedName(_ raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let filtered = lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") }
        var result = String(filtered)
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static var samples: [ServiceAlias] {
        [
            ServiceAlias(name: "web", localPort: 8080, notes: "OrbStack web service"),
            ServiceAlias(name: "api", localPort: 3000, enabled: false, notes: "API"),
        ]
    }
}
