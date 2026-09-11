import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, easyURLs, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .easyURLs: return "Easy URLs"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .easyURLs: return "link"
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
    @Environment(AppUpdater.self) private var updater
    @State private var selection: SettingsPane? = .easyURLs
    @State private var copiedEndpoint = false
    private let endpoint = "http://127.0.0.1:19247"

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 220)
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 440, idealHeight: 480)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection ?? .easyURLs {
        case .general:
            SettingsDetail(title: "General", symbol: SettingsPane.general.symbol) {
                settingsCard {
                    toggleRow(
                        title: "Open at Login",
                        subtitle: "Start Lantern automatically when you log in."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.store.launchAtLogin },
                            set: { enabled in
                                model.store.launchAtLogin = enabled
                                model.store.save()
                                try? setLaunchAtLogin(enabled)
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(LanternTheme.accent)
                    }
                }

                settingsCard {
                    toggleRow(
                        title: "Check for Updates Automatically",
                        subtitle: "Looks for a new GitHub Release about once a day."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(LanternTheme.accent)
                    }
                }
            }
        case .easyURLs:
            SettingsDetail(title: "Easy URLs", symbol: SettingsPane.easyURLs.symbol) {
                settingsCard {
                    toggleRow(
                        title: "Hide the port in the URL",
                        subtitle: "Share http://probus.local instead of http://probus.local:5173."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { model.store.proxyEnabled },
                            set: {
                                model.store.proxyEnabled = $0
                                model.store.save()
                                Task { await model.reconcile() }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(LanternTheme.accent)
                    }
                }

                if model.store.proxyEnabled {
                    settingsCard(title: "Link style") {
                        VStack(alignment: .leading, spacing: 10) {
                            modeRow(
                                title: "No port",
                                subtitle: "http://name.local",
                                selected: urlMode == .portless
                            ) {
                                applyURLMode(.portless)
                            }
                            Divider().opacity(0.35)
                            modeRow(
                                title: "Backup port",
                                subtitle: "http://name.local:8787 — if port 80 is blocked",
                                selected: urlMode == .backup
                            ) {
                                applyURLMode(.backup)
                            }
                        }
                    }

                    settingsCard(title: "Example") {
                        Text(verbatim: exampleURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                settingsCard(title: "Status") {
                    HStack {
                        Text("Right now")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(friendlyProxyStatus)
                            .foregroundStyle(proxyStatusColor)
                            .multilineTextAlignment(.trailing)
                    }
                    if model.canSuggestAlternateProxyPort {
                        Divider().opacity(0.35)
                        Button("Port 80 blocked — use backup links") {
                            model.useAlternateProxyPort(8787)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        case .advanced:
            SettingsDetail(title: "Advanced", symbol: SettingsPane.advanced.symbol) {
                settingsCard(title: "Control API") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: endpoint)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Loopback only. For scripts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Label(
                                copiedEndpoint ? "Copied" : "Copy endpoint",
                                systemImage: copiedEndpoint ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .about:
            SettingsDetail(title: "About", symbol: SettingsPane.about.symbol) {
                settingsCard {
                    infoRow("Version", AppVersion.display)
                    Divider().opacity(0.35)
                    infoRow("LAN", model.network.statusLabel)
                    Divider().opacity(0.35)
                    infoRow("Broadcast", model.store.masterBroadcastEnabled ? "On" : "Off")
                    Divider().opacity(0.35)
                    infoRow("Services", "\(model.store.aliases.count)")
                    Divider().opacity(0.35)
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func toggleRow<Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func modeRow(
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? LanternTheme.accent : .secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.system(size: 13))
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
        if !model.store.proxyEnabled { return "http://probus.local:5173" }
        return urlMode == .portless ? "http://probus.local" : "http://probus.local:8787"
    }

    private var friendlyProxyStatus: String {
        if !model.store.proxyEnabled { return "Off — URLs include each app’s port" }
        if model.proxyRunning {
            return urlMode == .portless ? "Ready — portless links work" : "Ready — use :8787 links"
        }
        if model.proxyBindFailed {
            return urlMode == .portless ? "Port 80 blocked" : "Couldn’t start on 8787"
        }
        if !model.store.masterBroadcastEnabled { return "Turn on Broadcast in the menu" }
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

private struct SettingsDetail<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LanternTheme.accent)
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                }

                content
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
