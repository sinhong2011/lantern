import Foundation
import Observation
import os

@MainActor
@Observable
final class AccessLogStore {
    private static let proxyLog = Logger(subsystem: "app.lantern", category: "proxy")
    private static let appLog = Logger(subsystem: "app.lantern", category: "app")
    private let limit = 300
    private let persist: Bool
    let fileURL: URL

    private(set) var entries: [LogEntry] = []

    var events: [AccessEvent] {
        entries.compactMap(\.access)
    }

    init(fileURL: URL? = nil, persist: Bool = true) {
        self.fileURL = fileURL ?? LanternPaths.logFile
        self.persist = persist
        if persist {
            if !FileManager.default.fileExists(atPath: self.fileURL.path) {
                try? Data().write(to: self.fileURL, options: .atomic)
            }
            entries = Self.loadTail(from: self.fileURL, limit: limit)
        }
    }

    /// Hop from the proxy's background queue onto the main actor.
    nonisolated func record(_ event: AccessEvent) {
        Task { @MainActor in
            self.append(.access(event))
        }
    }

    func recordActivity(_ kind: ActivityEvent.Kind, _ message: String, host: String? = nil) {
        append(.activity(ActivityEvent(kind: kind, message: message, host: host)))
    }

    func append(_ entry: LogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        Self.writeConsole(entry)
        if persist {
            Self.appendLine(entry, to: fileURL)
        }
    }

    func clear() {
        entries.removeAll()
        if persist {
            try? Data().write(to: fileURL, options: .atomic)
        }
    }

    func recent(for alias: ServiceAlias, limit: Int = 3) -> [AccessEvent] {
        Array(events.lazy.filter { $0.matches(alias: alias) }.prefix(limit))
    }

    func lastHit(for alias: ServiceAlias) -> Date? {
        events.first { $0.matches(alias: alias) }?.at
    }

    func filtered(kind: LogKindFilter, host: String?, query: String) -> [LogEntry] {
        entries.filter { entry in
            switch (kind, entry) {
            case (.access, .activity), (.activity, .access):
                return false
            case (_, .access(let event)):
                if let host, !event.matches(host: host) { return false }
                return event.matches(query: query)
            case (_, .activity(let event)):
                if let host, !event.matches(host: host) { return false }
                return event.matches(query: query)
            }
        }
    }

    private static func loadTail(from url: URL, limit: Int) -> [LogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(whereSeparator: \.isNewline).suffix(limit)
        return lines.reversed().compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return LogEntry(jsonObject: object)
        }
    }

    private static func appendLine(_ entry: LogEntry, to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: entry.jsonObject),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    private static func writeConsole(_ entry: LogEntry) {
        switch entry {
        case .access(let event):
            let line = "\(event.method) \(event.path) host=\(event.displayHost) client=\(event.displayClient) outcome=\(event.outcome.rawValue)"
            if event.outcome.isFailure {
                proxyLog.error("\(line, privacy: .public)")
            } else {
                proxyLog.info("\(line, privacy: .public)")
            }
        case .activity(let event):
            let line = "\(event.kind.rawValue) \(event.message)"
            if event.isFailure {
                appLog.error("\(line, privacy: .public)")
            } else {
                appLog.info("\(line, privacy: .public)")
            }
        }
    }
}

enum LogKindFilter: String, CaseIterable, Identifiable {
    case all, access, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .access: return "Access"
        case .activity: return "Activity"
        }
    }
}
