import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, broadcast, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .broadcast: return "Easy URLs"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .broadcast: return "link"
        case .advanced: return "terminal"
        case .about: return "info.circle"
        }
    }
}

private enum URLMode: Hashable {
    case portless
    case backup
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SettingsPane? = .general
    @State private var copiedEndpoint = false
    private let endpoint = "http://127.0.0.1:19247"

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 210)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 420, idealHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            detailShell("General", SettingsPane.general.symbol) {
                Form {
                    Section {
                        Toggle(isOn: Binding(
                            get: { model.store.launchAtLogin },
                            set: { enabled in
                                model.store.launchAtLogin = enabled
                                model.store.save()
                                try? setLaunchAtLogin(enabled)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open at Login")
                                Text("Keep Lantern ready in the menu bar.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }
                .formStyle(.grouped)
            }
        case .broadcast:
            detailShell("Easy URLs", SettingsPane.broadcast.symbol) {
                Form {
                    Section {
                        Toggle(isOn: Binding(
                            get: { model.store.proxyEnabled },
                            set: {
                                model.store.proxyEnabled = $0
                                model.store.save()
                                Task { await model.reconcile() }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide the port in the URL")
                                Text("Friends open http://probus.local — not http://probus.local:5173.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)
                    } footer: {
                        Text("Lantern listens on your Mac and quietly forwards each name to the right local app.")
                    }

                    if model.store.proxyEnabled {
                        Section {
                            Picker(selection: Binding(
                                get: { urlMode },
                                set: { applyURLMode($0) }
                            )) {
                                Text("No port (recommended)").tag(URLMode.portless)
                                Text("Backup port 8787").tag(URLMode.backup)
                            } label: {
                                Text("Link style")
                            }
                            .pickerStyle(.radioGroup)
                            .disabled(!model.store.proxyEnabled)

                            LabeledContent("Example") {
                                Text(verbatim: exampleURL)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } header: {
                            Text("How links look")
                        } footer: {
                            Text(urlModeFooter)
                        }
                    }

                    Section("Right now") {
                        LabeledContent("Status") {
                            Text(friendlyProxyStatus)
                                .foregroundStyle(proxyStatusColor)
                        }
                        if model.canSuggestAlternateProxyPort {
                            Button("Port 80 is blocked — switch to backup") {
                                model.useAlternateProxyPort(8787)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        case .advanced:
            detailShell("Advanced", SettingsPane.advanced.symbol) {
                Form {
                    Section {
                        LabeledContent("Control API") {
                            Text(endpoint)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(endpoint, forType: .string)
                            copiedEndpoint = true
                            model.showToast("Copied control API endpoint")
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                copiedEndpoint = false
                            }
                        } label: {
                            Label(copiedEndpoint ? "Copied" : "Copy Endpoint",
                                  systemImage: copiedEndpoint ? "checkmark" : "doc.on.doc")
                        }
                    } footer: {
                        Text("Loopback only. For scripts or a future Raycast extension.")
                    }
                }
                .formStyle(.grouped)
            }
        case .about:
            detailShell("About", SettingsPane.about.symbol) {
                Form {
                    Section {
                        LabeledContent("Version") { Text("0.1.0") }
                        LabeledContent("LAN") {
                            Text(model.network.statusLabel).textSelection(.enabled)
                        }
                        LabeledContent("Broadcast") {
                            Text(model.store.masterBroadcastEnabled ? "On" : "Off")
                        }
                        LabeledContent("Services") {
                            Text("\(model.store.aliases.count)")
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private func detailShell<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(LanternTheme.accent)
                        .font(.system(size: 16, weight: .semibold))
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 4)
                content()
            }
            .padding(20)
            .frame(maxWidth: 540, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var urlMode: URLMode {
        model.store.proxyPort == 80 ? .portless : .backup
    }

    private func applyURLMode(_ mode: URLMode) {
        model.store.proxyPort = mode == .portless ? 80 : 8787
        model.store.save()
        Task { await model.reconcile() }
    }

    private var exampleURL: String {
        if !model.store.proxyEnabled {
            return "http://probus.local:5173"
        }
        return urlMode == .portless ? "http://probus.local" : "http://probus.local:8787"
    }

    private var urlModeFooter: String {
        switch urlMode {
        case .portless:
            return "Best when it works. Some Macs block port 80 — use Backup if the status turns red."
        case .backup:
            return "Still short, but phones must use :8787. Prefer No port when your Mac allows it."
        }
    }

    private var friendlyProxyStatus: String {
        if !model.store.proxyEnabled {
            return "Off — URLs include each app’s port"
        }
        if model.proxyRunning {
            return urlMode == .portless
                ? "Ready — portless links work"
                : "Ready — use links with :8787"
        }
        if model.proxyBindFailed {
            return urlMode == .portless
                ? "Port 80 blocked on this Mac"
                : "Couldn’t start on 8787"
        }
        if !model.store.masterBroadcastEnabled {
            return "Turn on Broadcast in the menu to go live"
        }
        return "Waiting…"
    }

    private var proxyStatusColor: Color {
        if model.proxyRunning { return LanternTheme.live }
        if model.proxyBindFailed { return LanternTheme.danger }
        return .secondary
    }

    private func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}
