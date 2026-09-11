import Foundation
import Observation
import AppKit
import ServiceManagement

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
    private var reconcileTask: Task<Void, Never>?
    private var reconcileQueued = false

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
        syncLaunchAtLogin()
        scheduleReconcile()
    }

    func scheduleReconcile() {
        if reconcileTask != nil {
            reconcileQueued = true
            return
        }
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.reconcileQueued = false
                await self.reconcile()
            } while self.reconcileQueued
            self.reconcileTask = nil
        }
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
                lastError = nil
            } else {
                proxy.stop()
                proxyRunning = false
                proxyBindFailed = false
                lastError = nil
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
            // Clear stale bind errors once we are actually sharing, or no longer trying to.
            if proxyRunning || !store.proxyEnabled || !store.masterBroadcastEnabled {
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
        scheduleReconcile()
    }

    func useAlternateProxyPort(_ port: Int = 8787) {
        store.proxyEnabled = true
        store.proxyPort = port
        store.save()
        showToast("Proxy moved to :\(port)")
        scheduleReconcile()
    }

    func addSampleWebService() {
        guard !store.hasName("web") else {
            lastError = "web.local is already used."
            return
        }
        let sample = ServiceAlias(
            name: "web",
            localPort: 8080,
            notes: "OrbStack / docker -p"
        )
        upsertTracked(sample, existed: false)
        expandedServiceID = sample.id
        showToast("Added web.local → localhost:8080")
        scheduleReconcile()
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
            return "This Mac can’t use a portless link (port 80 needs permission or is busy)."
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
        scheduleReconcile()
    }

    func deleteAlias(_ alias: ServiceAlias) {
        if expandedServiceID == alias.id {
            expandedServiceID = nil
        }
        removeTracked(alias)
        scheduleReconcile()
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
        if store.hasName(name, except: editingAlias?.id) {
            lastError = "\(name).local is already used."
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
        scheduleReconcile()
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

    @discardableResult
    func copyLanIP() -> String? {
        guard let ip = network.lanIPv4 else {
            showToast("No LAN IP yet")
            return nil
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        showToast("Copied \(ip)")
        return ip
    }

    @discardableResult
    func copyFallbackURL(for alias: ServiceAlias) -> String? {
        guard let url = alias.fallbackURL(
            lanIP: network.lanIPv4,
            proxyPort: store.proxyPort,
            proxyEnabled: store.proxyEnabled && proxyRunning
        ) else {
            showToast("No LAN IP yet")
            return nil
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast("Copied \(url)")
        return url
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            store.launchAtLogin = enabled
            store.save()
        } catch {
            lastError = "Couldn't update Login Items. Check System Settings → Login Items."
            store.launchAtLogin = SMAppService.mainApp.status == .enabled
            store.save()
        }
    }

    func syncLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled:
            store.launchAtLogin = true
        case .requiresApproval:
            store.launchAtLogin = true
            lastError = "Open at Login needs approval in System Settings → Login Items."
        default:
            if store.launchAtLogin {
                lastError = "Open at Login is off in System Settings → Login Items."
            }
            store.launchAtLogin = false
        }
        store.save()
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
    func handleControl(method: String, path: String, body: Data) -> ControlResponse {
        let components = path.split(separator: "/").map(String.init)

        if method == "GET" && (path == "/status" || path == "/") {
            return .ok(statusDictionary())
        }

        if method == "GET" && path == "/aliases" {
            return .ok([
                "ok": true,
                "aliases": store.aliases.map(aliasDictionary),
            ])
        }

        if method == "GET" && path == "/logs" {
            return .ok([
                "ok": true,
                "file": logs.fileURL.path,
                "events": logs.entries.prefix(100).map(\.jsonObject),
            ])
        }

        if method == "DELETE" && path == "/logs" {
            logs.clear()
            return .ok()
        }

        if method == "POST" && path == "/broadcast" {
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let enabled = json["enabled"] as? Bool {
                setMasterBroadcast(enabled)
                return .ok(statusDictionary())
            }
            return .error(400, "expected {enabled:bool}")
        }

        if method == "POST" && path == "/aliases" {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let name = json["name"] as? String,
                  let port = json["localPort"] as? Int else {
                return .error(400, "expected {name, localPort}")
            }
            if store.hasName(name) {
                return .error(409, "\(ServiceAlias.sanitizedName(name)).local is already used")
            }
            let alias = ServiceAlias(
                name: name,
                localPort: port,
                enabled: (json["enabled"] as? Bool) ?? true,
                notes: (json["notes"] as? String) ?? ""
            )
            upsertTracked(alias, existed: false)
            scheduleReconcile()
            return .ok(["ok": true, "alias": aliasDictionary(alias)])
        }

        if components.count == 2 && components[0] == "aliases" {
            let idString = components[1]
            guard let id = UUID(uuidString: idString) else {
                return .error(400, "bad id")
            }
            if method == "DELETE" {
                if let alias = store.aliases.first(where: { $0.id == id }) {
                    removeTracked(alias)
                }
                scheduleReconcile()
                return .ok()
            }
            if method == "PATCH",
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               var alias = store.aliases.first(where: { $0.id == id }) {
                if let name = json["name"] as? String {
                    let next = ServiceAlias.sanitizedName(name)
                    if store.hasName(next, except: id) {
                        return .error(409, "\(next).local is already used")
                    }
                    alias.name = next
                }
                if let port = json["localPort"] as? Int { alias.localPort = port }
                if let enabled = json["enabled"] as? Bool { alias.enabled = enabled }
                if let notes = json["notes"] as? String { alias.notes = notes }
                upsertTracked(alias, existed: true)
                scheduleReconcile()
                return .ok(["ok": true, "alias": aliasDictionary(alias)])
            }
        }

        if method == "POST" && path == "/reconcile" {
            scheduleReconcile()
            return .ok()
        }

        return .error(404, "not found")
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
            "ipUrl": alias.fallbackURL(
                lanIP: network.lanIPv4,
                proxyPort: store.proxyPort,
                proxyEnabled: store.proxyEnabled && proxyRunning
            ) as Any,
        ]
    }
}
