import Foundation

struct ActivityEvent: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable {
        case broadcastOn
        case broadcastOff
        case proxyBound
        case proxyBindFailed
        case proxyStopped
        case serviceAdded
        case serviceUpdated
        case serviceRemoved
        case serviceToggled
    }

    let id: UUID
    let at: Date
    let kind: Kind
    let message: String
    let host: String?

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: Kind,
        message: String,
        host: String? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.message = message
        self.host = host
    }

    var timeText: String {
        at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    var isFailure: Bool {
        kind == .proxyBindFailed
    }

    var label: String {
        switch kind {
        case .broadcastOn, .broadcastOff: return "Broadcast"
        case .proxyBound, .proxyBindFailed, .proxyStopped: return "Proxy"
        case .serviceAdded, .serviceUpdated, .serviceRemoved, .serviceToggled: return "Service"
        }
    }

    var symbolName: String {
        switch kind {
        case .broadcastOn: return "antenna.radiowaves.left.and.right"
        case .broadcastOff: return "antenna.radiowaves.left.and.right"
        case .proxyBound: return "network"
        case .proxyBindFailed: return "exclamationmark.triangle.fill"
        case .proxyStopped: return "stop.circle"
        case .serviceAdded: return "plus"
        case .serviceUpdated: return "pencil"
        case .serviceRemoved: return "minus"
        case .serviceToggled: return "switch.2"
        }
    }

    var copyLine: String {
        [timeText, label, message].joined(separator: "  ")
    }

    func matches(host raw: String) -> Bool {
        guard let host else { return false }
        let key = raw.lowercased().replacingOccurrences(of: ".local", with: "")
        let h = host.lowercased()
        return h == key || h == "\(key).local"
    }

    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return message.lowercased().contains(q)
            || kind.rawValue.lowercased().contains(q)
            || label.lowercased().contains(q)
            || (host?.lowercased().contains(q) ?? false)
    }
}

enum LogEntry: Identifiable, Sendable, Equatable {
    case access(AccessEvent)
    case activity(ActivityEvent)

    var id: UUID {
        switch self {
        case .access(let event): return event.id
        case .activity(let event): return event.id
        }
    }

    var at: Date {
        switch self {
        case .access(let event): return event.at
        case .activity(let event): return event.at
        }
    }

    var copyLine: String {
        switch self {
        case .access(let event): return event.copyLine
        case .activity(let event): return event.copyLine
        }
    }

    var timeText: String {
        switch self {
        case .access(let event): return event.timeText
        case .activity(let event): return event.timeText
        }
    }

    var kindText: String {
        switch self {
        case .access(let event): return event.method
        case .activity(let event): return event.label
        }
    }

    var detailText: String {
        switch self {
        case .access(let event): return event.path
        case .activity(let event): return event.message
        }
    }

    var hostText: String {
        switch self {
        case .access(let event): return event.displayHost
        case .activity(let event): return event.host ?? ""
        }
    }

    var clientText: String {
        switch self {
        case .access(let event): return event.displayClient == "—" ? "" : event.displayClient
        case .activity: return ""
        }
    }

    var statusText: String {
        switch self {
        case .access(let event): return event.outcome.label
        case .activity: return ""
        }
    }

    var isFailure: Bool {
        switch self {
        case .access(let event): return event.outcome.isFailure
        case .activity(let event): return event.isFailure
        }
    }

    var access: AccessEvent? {
        if case .access(let event) = self { return event }
        return nil
    }

    init?(jsonObject: [String: Any]) {
        let kind = jsonObject["kind"] as? String
        let id = (jsonObject["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let at: Date = {
            if let raw = jsonObject["at"] as? String {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: raw) { return date }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: raw) { return date }
            }
            return Date()
        }()
        if kind == "activity" {
            guard let raw = jsonObject["activity"] as? String,
                  let activity = ActivityEvent.Kind(rawValue: raw),
                  let message = jsonObject["message"] as? String else { return nil }
            self = .activity(ActivityEvent(
                id: id,
                at: at,
                kind: activity,
                message: message,
                host: jsonObject["host"] as? String
            ))
            return
        }
        guard let method = jsonObject["method"] as? String,
              let path = jsonObject["path"] as? String,
              let host = jsonObject["host"] as? String,
              let outcomeRaw = jsonObject["outcome"] as? String,
              let outcome = AccessEvent.Outcome(rawValue: outcomeRaw) else { return nil }
        self = .access(AccessEvent(
            id: id,
            at: at,
            method: method,
            path: path,
            host: host,
            client: jsonObject["client"] as? String,
            localPort: jsonObject["localPort"] as? Int,
            outcome: outcome
        ))
    }

    var jsonObject: [String: Any] {
        switch self {
        case .access(let event):
            [
                "kind": "access",
                "id": event.id.uuidString,
                "at": event.at.formatted(.iso8601),
                "method": event.method,
                "path": event.path,
                "host": event.host,
                "client": event.client as Any,
                "localPort": event.localPort as Any,
                "outcome": event.outcome.rawValue,
            ]
        case .activity(let event):
            [
                "kind": "activity",
                "id": event.id.uuidString,
                "at": event.at.formatted(.iso8601),
                "activity": event.kind.rawValue,
                "message": event.message,
                "host": event.host as Any,
            ]
        }
    }
}
