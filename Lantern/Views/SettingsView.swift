import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, logs, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .logs: return "Logs"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .logs: return "list.bullet.rectangle"
        case .advanced: return "terminal"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppUpdater.self) private var updater
    @State private var selection: SettingsPane = .general
    @State private var copiedEndpoint = false
    @State private var copiedToken = false
    private let endpoint = "http://127.0.0.1:19247"

    var body: some View {
        TabView(selection: $selection) {
            settingsPage { generalPane }
                .tabItem { Label(SettingsPane.general.title, systemImage: SettingsPane.general.symbol) }
                .tag(SettingsPane.general)

            settingsPage(scrolls: false) { LogsSettingsView() }
                .tabItem { Label(SettingsPane.logs.title, systemImage: SettingsPane.logs.symbol) }
                .tag(SettingsPane.logs)

            settingsPage { advancedPane }
                .tabItem { Label(SettingsPane.advanced.title, systemImage: SettingsPane.advanced.symbol) }
                .tag(SettingsPane.advanced)

            settingsPage { aboutPane }
                .tabItem { Label(SettingsPane.about.title, systemImage: SettingsPane.about.symbol) }
                .tag(SettingsPane.about)
        }
        .frame(width: 560, height: 480)
    }

    private func settingsPage<Content: View>(
        scrolls: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if scrolls {
                ScrollView {
                    content()
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content()
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard {
                toggleRow(
                    title: "Open at Login",
                    subtitle: "Start Lantern automatically when you log in."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.store.launchAtLogin },
                        set: { model.applyLaunchAtLogin($0) }
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

            settingsCard {
                toggleRow(
                    title: "Share one LAN name",
                    subtitle: "Phones open http://\(exampleHost) instead of each app’s own port."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.store.proxyEnabled },
                        set: {
                            model.store.proxyEnabled = $0
                            model.store.save()
                            model.scheduleReconcile()
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(LanternTheme.accent)
                }
            }

            settingsCard(title: "What others open") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: shareURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text(shareExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.store.proxyEnabled && model.store.proxyPort != 80 && !model.canSuggestAlternateProxyPort {
                        Button("Try a portless link") {
                            model.useAlternateProxyPort(80)
                        }
                        .buttonStyle(.link)
                    }
                    HStack {
                        Text("Right now")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(friendlyProxyStatus)
                            .foregroundStyle(proxyStatusColor)
                    }
                    .font(.system(size: 12))
                    if model.canSuggestAlternateProxyPort {
                        Button("Keep sharing without port 80") {
                            model.useAlternateProxyPort(8787)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var advancedPane: some View {
        settingsCard(title: "Control API") {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: endpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("127.0.0.1 only. Writes need \(ControlToken.headerName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ControlToken.current())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
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
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ControlToken.current(), forType: .string)
                        copiedToken = true
                        model.showToast("Copied control token")
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            copiedToken = false
                        }
                    } label: {
                        Label(
                            copiedToken ? "Copied" : "Copy token",
                            systemImage: copiedToken ? "checkmark" : "key"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var aboutPane: some View {
        settingsCard {
            VStack(spacing: 10) {
                Image("LanternLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                    .accessibilityLabel("Lantern")
                Text("Lantern")
                    .font(.system(size: 18, weight: .semibold))
                Text("Portless LAN names for local apps")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            Divider().opacity(0.35)
            infoRow("Version", AppVersion.display)
            Divider().opacity(0.35)
            infoRow("Author", LanternLinks.authorName)
            Divider().opacity(0.35)
            Button {
                NSWorkspace.shared.open(LanternLinks.author)
            } label: {
                HStack {
                    Text("GitHub").foregroundStyle(.secondary)
                    Spacer()
                    Text(LanternLinks.authorHandle)
                        .fontWeight(.medium)
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            Divider().opacity(0.35)
            Button {
                NSWorkspace.shared.open(LanternLinks.repo)
            } label: {
                HStack {
                    Text("Repository").foregroundStyle(.secondary)
                    Spacer()
                    Text(LanternLinks.repoLabel)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
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

    private var exampleHost: String {
        "\(model.store.aliases.first?.name ?? "myapp").local"
    }

    private var shareURL: String {
        if let alias = model.store.aliases.first {
            return alias.publicURL(
                lanIP: model.network.lanIPv4,
                proxyPort: model.store.proxyPort,
                proxyEnabled: model.store.proxyEnabled
            )
        }
        if model.store.proxyEnabled {
            return model.store.proxyPort == 80 ? "http://\(exampleHost)" : "http://\(exampleHost):\(model.store.proxyPort)"
        }
        return "http://\(exampleHost):8080"
    }

    private var shareExplanation: String {
        if !model.store.proxyEnabled {
            return "Each app keeps its own port in the link."
        }
        if model.store.proxyPort == 80 {
            return "No port to type — this is the default web address on a LAN."
        }
        return "The number is Lantern’s door on this Mac, not the app’s port. Every service uses this same address."
    }

    private var friendlyProxyStatus: String {
        if !model.store.proxyEnabled { return "Off — each app uses its own port" }
        if model.proxyRunning {
            return model.store.proxyPort == 80 ? "Ready" : "Ready — same name for every app"
        }
        if model.proxyBindFailed {
            return model.store.proxyPort == 80 ? "Portless links blocked on this Mac" : "Couldn’t start sharing"
        }
        if !model.store.masterBroadcastEnabled { return "Turn on Broadcast in the menu" }
        return "Waiting…"
    }

    private var proxyStatusColor: Color {
        if model.proxyRunning { return LanternTheme.live }
        if model.proxyBindFailed { return LanternTheme.danger }
        return .secondary
    }
}
