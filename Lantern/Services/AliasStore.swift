import Foundation
import Observation

@MainActor
@Observable
final class AliasStore {
    private(set) var aliases: [ServiceAlias] = []
    var masterBroadcastEnabled: Bool = false
    var proxyEnabled: Bool = true
    var proxyPort: Int = 8787
    var launchAtLogin: Bool = false

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Lantern", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? LanternPaths.stateFile
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            aliases = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            aliases = decoded.aliases
            masterBroadcastEnabled = decoded.masterBroadcastEnabled
            proxyEnabled = decoded.proxyEnabled
            launchAtLogin = decoded.launchAtLogin
            let version = decoded.schemaVersion ?? 1
            // Pre-0.2 files defaulted to :80. Keep :80 only after the user opts in (schema 2+).
            proxyPort = version < PersistedState.currentSchema && decoded.proxyPort == 80
                ? 8787
                : decoded.proxyPort
            if version < PersistedState.currentSchema {
                save()
            }
        } catch {
            aliases = []
        }
    }

    func save() {
        let state = PersistedState(
            aliases: aliases,
            masterBroadcastEnabled: masterBroadcastEnabled,
            proxyEnabled: proxyEnabled,
            proxyPort: proxyPort,
            launchAtLogin: launchAtLogin,
            schemaVersion: PersistedState.currentSchema
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func upsert(_ alias: ServiceAlias) {
        if let idx = aliases.firstIndex(where: { $0.id == alias.id }) {
            aliases[idx] = alias
        } else {
            aliases.insert(alias, at: 0)
        }
        save()
    }

    func remove(id: UUID) {
        aliases.removeAll { $0.id == id }
        save()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let idx = aliases.firstIndex(where: { $0.id == id }) else { return }
        aliases[idx].enabled = enabled
        save()
    }

    func setMasterBroadcast(_ enabled: Bool) {
        masterBroadcastEnabled = enabled
        save()
    }

    var activeAliases: [ServiceAlias] {
        aliases.filter(\.enabled)
    }

    func hasName(_ name: String, except id: UUID? = nil) -> Bool {
        let key = ServiceAlias.sanitizedName(name)
        return aliases.contains { $0.name == key && $0.id != id }
    }
}

private struct PersistedState: Codable {
    static let currentSchema = 2

    var aliases: [ServiceAlias]
    var masterBroadcastEnabled: Bool
    var proxyEnabled: Bool
    var proxyPort: Int
    var launchAtLogin: Bool
    var schemaVersion: Int?
}
