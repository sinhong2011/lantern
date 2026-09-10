import SwiftUI

struct ServiceRowView: View {
    @Environment(AppModel.self) private var model
    let alias: ServiceAlias
    @State private var confirmDelete = false
    @State private var copied = false

    private var isLive: Bool {
        alias.enabled && model.store.masterBroadcastEnabled
    }

    private var publicURL: String {
        alias.publicURL(
            lanIP: model.network.lanIPv4,
            proxyPort: model.store.proxyPort,
            proxyEnabled: model.store.proxyEnabled && model.proxyRunning
        )
    }

    private var metaLine: String {
        var parts = ["localhost\(LanternTheme.portText(alias.localPort))"]
        if !alias.notes.isEmpty { parts.append(alias.notes) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LanternSection {
            // Header — BetterDisplay display title row
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(alias.hostName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if isLive {
                            Circle()
                                .fill(LanternTheme.live)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(metaLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Toggle("", isOn: Binding(
                    get: { alias.enabled },
                    set: { _ in model.toggleAlias(alias) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(LanternTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Primary action
            LanternPrimaryButton(title: openButtonTitle) {
                model.openURL(for: alias)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            divider

            LanternMenuRow(
                title: copied ? "Copied Link" : "Copy Link",
                symbol: copied ? "checkmark" : "link",
                chevron: false
            ) {
                model.copyURL(for: alias)
                copied = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    copied = false
                }
            }

            divider.padding(.leading, 40)

            LanternMenuRow(title: "Edit Service", symbol: "slider.horizontal.3") {
                model.beginEdit(alias)
            }

            divider.padding(.leading, 40)

            LanternMenuRow(title: "Remove", symbol: "trash", chevron: false, destructive: true) {
                confirmDelete = true
            }
            .padding(.bottom, 4)
        }
        .confirmationDialog(
            "Remove \(alias.hostName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                model.deleteAlias(alias)
                model.showToast("Removed \(alias.hostName)")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops sharing this name on your LAN.")
        }
        .animation(.easeOut(duration: 0.12), value: copied)
    }

    private var openButtonTitle: String {
        if publicURL.hasPrefix("http://") {
            return "Open \(publicURL.replacingOccurrences(of: "http://", with: ""))"
        }
        return "Open \(publicURL)"
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}
