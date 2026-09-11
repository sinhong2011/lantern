import SwiftUI

struct ServiceRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let alias: ServiceAlias
    @State private var confirmDelete = false
    @State private var copied = false

    private var isLive: Bool {
        alias.enabled && model.store.masterBroadcastEnabled
    }

    private var isExpanded: Bool {
        model.expandedServiceID == alias.id
    }

    private var publicURL: String {
        alias.publicURL(
            lanIP: model.network.lanIPv4,
            proxyPort: model.store.proxyPort,
            proxyEnabled: model.store.proxyEnabled && model.proxyRunning
        )
    }

    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1)
    }

    var body: some View {
        LanternSection {
            VStack(spacing: 0) {
                header

                expandedBody
                    .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                    .opacity(isExpanded ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
        }
        .animation(expandAnimation, value: isExpanded)
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

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(expandAnimation) {
                    model.toggleExpandedService(alias.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isLive ? LanternTheme.accent : .secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(alias.notes.isEmpty ? alias.hostName : alias.notes)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if isLive {
                                Circle()
                                    .fill(LanternTheme.live)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        Text(shortURL)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")

            Toggle("", isOn: Binding(
                get: { alias.enabled },
                set: { _ in model.toggleAlias(alias) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .tint(LanternTheme.accent)

            Button {
                withAnimation(expandAnimation) {
                    model.toggleExpandedService(alias.id)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            divider

            LanternMenuRow(
                title: "Open in Browser",
                symbol: "safari",
                detail: shortURL,
                chevron: true
            ) {
                model.openURL(for: alias)
            }

            divider.padding(.leading, 40)

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
    }

    private var shortURL: String {
        publicURL
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}
