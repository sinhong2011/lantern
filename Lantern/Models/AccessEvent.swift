import Foundation

struct AccessEvent: Identifiable, Sendable, Equatable {
    enum Outcome: String, Sendable {
        case forwarded
        case unknownHost
        case missingHost
        case upstreamDown

        var label: String {
            switch self {
            case .forwarded: return "Forwarded"
            case .unknownHost: return "Unknown host"
            case .missingHost: return "Missing host"
            case .upstreamDown: return "Upstream down"
            }
        }

        var isFailure: Bool {
            self != .forwarded
        }
    }

    let id: UUID
    let at: Date
    let method: String
    let path: String
    let host: String
    let client: String?
    let localPort: Int?
    let outcome: Outcome

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        method: String,
        path: String,
        host: String,
        client: String?,
        localPort: Int?,
        outcome: Outcome
    ) {
        self.id = id
        self.at = at
        self.method = method
        self.path = path
        self.host = host
        self.client = client
        self.localPort = localPort
        self.outcome = outcome
    }

    var timeText: String {
        at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    var displayHost: String {
        host.isEmpty ? "—" : host
    }

    var displayClient: String {
        client ?? "—"
    }

    var copyLine: String {
        [timeText, method, path, displayHost, displayClient, outcome.label]
            .joined(separator: "  ")
    }

    func matches(alias: ServiceAlias) -> Bool {
        matches(host: alias.hostName)
    }

    func matches(host raw: String) -> Bool {
        let h = host.lowercased()
        let key = raw.lowercased().replacingOccurrences(of: ".local", with: "")
        return h == key || h == "\(key).local"
    }

    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return method.lowercased().contains(q)
            || path.lowercased().contains(q)
            || host.lowercased().contains(q)
            || (client?.lowercased().contains(q) ?? false)
            || outcome.label.lowercased().contains(q)
    }
}

enum HTTPAccess {
    static let maxPathLength = 200

    static func requestLine(from headerBlock: Data) -> (method: String, path: String) {
        let text = String(data: headerBlock, encoding: .utf8)
            ?? String(data: headerBlock, encoding: .ascii)
            ?? ""
        let first = text.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        let method = parts.isEmpty ? "GET" : String(parts[0]).uppercased()
        var path = parts.count >= 2 ? String(parts[1]) : "/"
        if path.isEmpty { path = "/" }
        if path.count > maxPathLength {
            path = String(path.prefix(maxPathLength))
        }
        return (method, path)
    }

    static func isWebSocketUpgrade(_ headerBlock: Data) -> Bool {
        let text = String(data: headerBlock, encoding: .utf8)
            ?? String(data: headerBlock, encoding: .ascii)
            ?? ""
        for raw in text.split(separator: "\r\n") {
            let line = raw.lowercased()
            if line.hasPrefix("upgrade:"), line.contains("websocket") {
                return true
            }
        }
        return false
    }
}
