import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppModel {
    let store = AliasStore()
    let network = NetworkMonitor()
    let broadcast = BroadcastEngine()
    let proxy = LocalProxy()
    let logs = AccessLogStore()
    let control = ControlServer()

    var isBusy = false
    var lastError: String?
    var proxyBindFailed = false
    var proxyRunning = false
    var showingAddSheet = false
    var editingAlias: ServiceAlias?
    var draftName = ""
    var draftPort = "8080"
    var draftNotes = ""
    var toastMessage: String?
    /// BetterDisplay-style accordion: one expanded service section at a time.
    var expandedServiceID: UUID?
    private var toastToken = UUID()
    private var didStart = false
    private var lastBoundPort: Int?

    var statusTint: StatusTint {
        if lastError != nil || proxyBindFailed { return .error }
        if store.masterBroadcastEnabled && network.lanIPv4 != nil { return .live }
        if store.masterBroadcastEnabled { return .pending }
        return .idle
    }

    /// True when we can offer one-tap recovery to alternate proxy port.
    var canSuggestAlternateProxyPort: Bool {
        proxyBindFailed && store.proxyEnabled && store.proxyPort == 80
    }

    enum StatusTint {
        case idle, pending, live, error
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        network.start()
        control.attach(app: self)
        control.start()
        let logs = self.logs
        proxy.onAccess = { event in
            logs.record(event)
        }
        Task { await reconcile() }
    }

    func stop() {
        network.stop()
        control.stop()
        Task {
            await broadcast.stopAll()
            proxy.stop()
        }
    }

    func reconcile() async {
        isBusy = true
        defer { isBusy = false }

        let wasRunning = proxyRunning
        let wasFailed = proxyBindFailed

        // Keep control API / Raycast-optional consumers in sync via shared store file.
        store.save()

        do {
            if store.masterBroadcastEnabled && store.proxyEnabled {
                try await proxy.start(port: UInt16(store.proxyPort))
                proxy.updateRoutes(store.activeAliases)
                proxyRunning = true
                proxyBindFailed = false
            } else {
                proxy.stop()
                proxyRunning = false
                proxyBindFailed = false
            }
        } catch {
            proxyRunning = false
            proxyBindFailed = store.proxyEnabled && store.masterBroadcastEnabled
            lastError = Self.friendlyProxyError(error, port: store.proxyPort)
            // Still try mDNS with direct ports if proxy bind fails.
        }

        if store.masterBroadcastEnabled && store.proxyEnabled && proxyRunning {
            proxy.updateRoutes(store.activeAliases)
        }

        await broadcast.sync(
            aliases: store.aliases,
            lanIP: network.lanIPv4,
            masterEnabled: store.masterBroadcastEnabled,
            proxyEnabled: store.proxyEnabled && proxyRunning,
            proxyPort: store.proxyPort
        )

        if network.lanIPv4 != nil {
            // Clear stale bind errors once network is healthy and sync succeeded.
            if proxyRunning || !store.proxyEnabled {
                lastError = nil
                proxyBindFailed = false
            }
        }

        recordProxyActivity(wasRunning: wasRunning, wasFailed: wasFailed)
    }

    private func recordProxyActivity(wasRunning: Bool, wasFailed: Bool) {
        if proxyRunning, !wasRunning || lastBoundPort != store.proxyPort {
            logs.recordActivity(.proxyBound, "Proxy listening on :\(store.proxyPort)")
            lastBoundPort = store.proxyPort
        } else if !proxyRunning, wasRunning {
            logs.recordActivity(.proxyStopped, "Proxy stopped")
            lastBoundPort = nil
        }
        if proxyBindFailed, !wasFailed {
            logs.recordActivity(.proxyBindFailed, lastError ?? "Proxy bind failed")
        }
    }

    func setMasterBroadcast(_ enabled: Bool) {
        store.setMasterBroadcast(enabled)
        logs.recordActivity(enabled ? .broadcastOn : .broadcastOff, enabled ? "Broadcast on" : "Broadcast off")
        Task { await reconcile() }
    }

    func useAlternateProxyPort(_ port: Int = 8787) {
        store.proxyEnabled = true
        store.proxyPort = port
        store.save()
        showToast("Proxy moved to :\(port)")
        Task { await reconcile() }
    }

    func addSampleWebService() {
        let sample = ServiceAlias(
            name: "web",
            localPort: 8080,
            notes: "OrbStack / docker -p"
        )
        upsertTracked(sample, existed: false)
        expandedServiceID = sample.id
        showToast("Added web.local → localhost:8080")
        Task { await reconcile() }
    }

    func showToast(_ message: String) {
        let token = UUID()
        toastToken = token
        toastMessage = message
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard toastToken == token else { return }
            toastMessage = nil
        }
    }

    private static func friendlyProxyError(_ error: Error, port: Int) -> String {
        let raw = error.localizedDescription.lowercased()
        if port == 80 {
            return "Can't bind port 80 (needs permission or it's busy). Use 8787 for easy LAN URLs."
        }
        if raw.contains("address already") || raw.contains("in use") || raw.contains("conflict") {
            return "Port \(port) is already in use on this Mac."
        }
        if raw.contains("permission") || raw.contains("denied") {
            return "macOS blocked binding port \(port)."
        }
        return "Proxy couldn't start on port \(port)."
    }

    func toggleAlias(_ alias: ServiceAlias) {
        let enabled = !alias.enabled
        store.setEnabled(id: alias.id, enabled: enabled)
        logs.recordActivity(
            .serviceToggled,
            "\(alias.hostName) \(enabled ? "on" : "off")",
            host: alias.hostName
        )
        Task { await reconcile() }
    }

    func deleteAlias(_ alias: ServiceAlias) {
        if expandedServiceID == alias.id {
            expandedServiceID = nil
        }
        removeTracked(alias)
        Task { await reconcile() }
    }

    func setExpandedService(_ id: UUID?) {
        expandedServiceID = id
    }

    func toggleExpandedService(_ id: UUID) {
        expandedServiceID = expandedServiceID == id ? nil : id
    }

    func beginAdd() {
        editingAlias = nil
        draftName = ""
        draftPort = "8080"
        draftNotes = ""
        showingAddSheet = true
    }

    func beginEdit(_ alias: ServiceAlias) {
        editingAlias = alias
        draftName = alias.name
        draftPort = String(alias.localPort)
        draftNotes = alias.notes
        showingAddSheet = true
    }

    func cancelDraft() {
        showingAddSheet = false
        editingAlias = nil
    }

    func saveDraft() {
        let name = ServiceAlias.sanitizedName(draftName)
        guard !name.isEmpty, let port = Int(draftPort), (1...65535).contains(port) else {
            lastError = "Name and port (1–65535) are required."
            return
        }
        let wasEditing = editingAlias != nil
        let alias = ServiceAlias(
            id: editingAlias?.id ?? UUID(),
            name: name,
            localPort: port,
            enabled: editingAlias?.enabled ?? true,
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        upsertTracked(alias, existed: wasEditing)
        showingAddSheet = false
        expandedServiceID = alias.id
        showToast(wasEditing ? "Updated \(alias.hostName)" : "Added \(alias.hostName)")
        Task { await reconcile() }
    }

    @discardableResult
    func copyURL(for alias: ServiceAlias) -> String {
        let url = alias.publicURL(
            lanIP: network.lanIPv4,
            proxyPort: store.proxyPort,
            proxyEnabled: store.proxyEnabled && proxyRunning
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast("Copied \(url)")
        return url
    }

    func openURL(for alias: ServiceAlias) {
        let urlString = alias.publicURL(
            lanIP: network.lanIPv4,
            proxyPort: store.proxyPort,
            proxyEnabled: store.proxyEnabled && proxyRunning
        )
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// HTTP control plane for optional Raycast / scripts.
    func handleControl(method: String, path: String, body: Data) -> [String: Any] {
        let components = path.split(separator: "/").map(String.init)

        if method == "GET" && (path == "/status" || path == "/") {
            return statusDictionary()
        }

        if method == "GET" && path == "/aliases" {
            return [
                "ok": true,
                "aliases": store.aliases.map(aliasDictionary),
            ]
        }

        if method == "GET" && path == "/logs" {
            return [
                "ok": true,
                "events": logs.entries.prefix(100).map(logDictionary),
            ]
        }

        if method == "DELETE" && path == "/logs" {
            logs.clear()
            return ["ok": true]
        }

        if method == "POST" && path == "/broadcast" {
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let enabled = json["enabled"] as? Bool {
                setMasterBroadcast(enabled)
                return statusDictionary()
            }
            return ["ok": false, "error": "expected {enabled:bool}"]
        }

        if method == "POST" && path == "/aliases" {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let name = json["name"] as? String,
                  let port = json["localPort"] as? Int else {
                return ["ok": false, "error": "expected {name, localPort}"]
            }
            let alias = ServiceAlias(
                name: name,
                localPort: port,
                enabled: (json["enabled"] as? Bool) ?? true,
                notes: (json["notes"] as? String) ?? ""
            )
            upsertTracked(alias, existed: false)
            Task { await reconcile() }
            return ["ok": true, "alias": aliasDictionary(alias)]
        }

        if components.count == 2 && components[0] == "aliases" {
            let idString = components[1]
            guard let id = UUID(uuidString: idString) else {
                return ["ok": false, "error": "bad id"]
            }
            if method == "DELETE" {
                if let alias = store.aliases.first(where: { $0.id == id }) {
                    removeTracked(alias)
                }
                Task { await reconcile() }
                return ["ok": true]
            }
            if method == "PATCH",
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               var alias = store.aliases.first(where: { $0.id == id }) {
                if let name = json["name"] as? String { alias.name = ServiceAlias.sanitizedName(name) }
                if let port = json["localPort"] as? Int { alias.localPort = port }
                if let enabled = json["enabled"] as? Bool { alias.enabled = enabled }
                if let notes = json["notes"] as? String { alias.notes = notes }
                upsertTracked(alias, existed: true)
                Task { await reconcile() }
                return ["ok": true, "alias": aliasDictionary(alias)]
            }
        }

        if method == "POST" && path == "/reconcile" {
            Task { await reconcile() }
            return ["ok": true]
        }

        if method == "POST" && path == "/ui/edit" {
            if let alias = store.aliases.first {
                beginEdit(alias)
            } else {
                beginAdd()
            }
            return ["ok": true, "showingAddSheet": showingAddSheet]
        }

        if method == "POST" && path == "/ui/home" {
            cancelDraft()
            return ["ok": true]
        }

        return ["ok": false, "error": "not found"]
    }

    private func statusDictionary() -> [String: Any] {
        [
            "ok": true,
            "broadcast": store.masterBroadcastEnabled,
            "proxyEnabled": store.proxyEnabled,
            "proxyRunning": proxyRunning,
            "proxyPort": store.proxyPort,
            "lanIP": network.lanIPv4 as Any,
            "interface": network.interfaceName as Any,
            "error": lastError as Any,
            "aliases": store.aliases.map(aliasDictionary),
        ]
    }

    private func upsertTracked(_ alias: ServiceAlias, existed: Bool) {
        store.upsert(alias)
        logs.recordActivity(
            existed ? .serviceUpdated : .serviceAdded,
            existed
                ? "Updated \(alias.hostName) → localhost:\(alias.localPort)"
                : "Added \(alias.hostName) → localhost:\(alias.localPort)",
            host: alias.hostName
        )
    }

    private func removeTracked(_ alias: ServiceAlias) {
        store.remove(id: alias.id)
        logs.recordActivity(.serviceRemoved, "Removed \(alias.hostName)", host: alias.hostName)
    }

    private func logDictionary(_ entry: LogEntry) -> [String: Any] {
        switch entry {
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

    private func aliasDictionary(_ alias: ServiceAlias) -> [String: Any] {
        [
            "id": alias.id.uuidString,
            "name": alias.name,
            "host": alias.hostName,
            "localPort": alias.localPort,
            "enabled": alias.enabled,
            "notes": alias.notes,
            "url": alias.publicURL(
                lanIP: network.lanIPv4,
                proxyPort: store.proxyPort,
                proxyEnabled: store.proxyEnabled && proxyRunning
            ),
        ]
    }
}
