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
        case .broadcastOn: return "broadcast"
        case .broadcastOff: return "broadcast"
        case .proxyBound: return "proxy"
        case .proxyBindFailed: return "proxy"
        case .proxyStopped: return "proxy"
        case .serviceAdded: return "service"
        case .serviceUpdated: return "service"
        case .serviceRemoved: return "service"
        case .serviceToggled: return "service"
        }
    }

    var copyLine: String {
        "\(timeText) \(kind.rawValue) \(message)"
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
            || label.contains(q)
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
}
