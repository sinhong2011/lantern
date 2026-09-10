import Foundation
import Observation

@MainActor
@Observable
final class AliasStore {
    private(set) var aliases: [ServiceAlias] = []
    var masterBroadcastEnabled: Bool = false
    var proxyEnabled: Bool = true
    var proxyPort: Int = 80
    var launchAtLogin: Bool = false

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Lantern", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? dir.appendingPathComponent("state.json")
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
            proxyPort = decoded.proxyPort
            launchAtLogin = decoded.launchAtLogin
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
            launchAtLogin: launchAtLogin
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
}

private struct PersistedState: Codable {
    var aliases: [ServiceAlias]
    var masterBroadcastEnabled: Bool
    var proxyEnabled: Bool
    var proxyPort: Int
    var launchAtLogin: Bool
}
