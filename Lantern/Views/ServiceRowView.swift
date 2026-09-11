import SwiftUI

struct ServiceRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let alias: ServiceAlias
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var copiedIP = false

    private var isLive: Bool {
        alias.enabled && model.store.masterBroadcastEnabled
    }

    private var isExpanded: Bool {
        model.expandedServiceID == alias.id
    }

    private var recentHits: [AccessEvent] {
        model.logs.recent(for: alias, limit: 3)
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
                    serviceMark

                    VStack(alignment: .leading, spacing: 1) {
                        Text(alias.notes.isEmpty ? alias.hostName : alias.notes)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        subtitle
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowPressStyle())
            .help(isExpanded ? "Collapse" : "Expand")
            .accessibilityLabel(rowAccessibilityLabel)

            localPortChip

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
            .buttonStyle(MenuRowPressStyle())
            .help(isExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Control Center / Settings glyph well — filled when on the LAN, never a floating accent icon.
    private var serviceMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isLive ? LanternTheme.live : Color.primary.opacity(0.08))
            if isLive {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
            }
            Image(systemName: "network")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isLive ? Color.white : Color.secondary)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: 24, height: 24)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 1),
            value: isLive
        )
        .accessibilityHidden(true)
    }

    private var localPortChip: some View {
        Text(":\(alias.localPort)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .help("This Mac’s port")
            .accessibilityLabel("Local port \(alias.localPort)")
    }

    private var rowAccessibilityLabel: String {
        let title = alias.notes.isEmpty ? alias.hostName : alias.notes
        return isLive ? "\(title), port \(alias.localPort), broadcasting" : "\(title), port \(alias.localPort)"
    }

    @ViewBuilder
    private var subtitle: some View {
        if model.logs.lastHit(for: alias) != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(isJustNow(at: context.date) ? "just now" : shortURL)
            }
        } else {
            Text(shortURL)
        }
    }

    private func isJustNow(at date: Date) -> Bool {
        guard let last = model.logs.lastHit(for: alias) else { return false }
        return date.timeIntervalSince(last) < 10
    }

    private var recentHitsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if recentHits.isEmpty {
                Text("No requests yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(recentHits) { event in
                    HStack(spacing: 8) {
                        Text(event.method)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(event.outcome.isFailure ? LanternTheme.danger : LanternTheme.accent)
                            .frame(width: 36, alignment: .leading)
                        Text(event.outcome.isFailure ? event.outcome.label : event.path)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(event.outcome.isFailure ? LanternTheme.danger : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(event.timeText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recentHits.isEmpty ? "No requests yet" : "\(recentHits.count) recent requests")
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            recentHitsBlock

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

            if let ipURL = fallbackURL {
                LanternMenuRow(
                    title: copiedIP ? "Copied LAN Address" : "Copy LAN Address",
                    symbol: copiedIP ? "checkmark" : "antenna.radiowaves.left.and.right",
                    detail: ipURL.replacingOccurrences(of: "http://", with: ""),
                    chevron: false
                ) {
                    model.copyFallbackURL(for: alias)
                    copiedIP = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(1200))
                        copiedIP = false
                    }
                }
                divider.padding(.leading, 40)
            }

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

    private var fallbackURL: String? {
        alias.fallbackURL(
            lanIP: model.network.lanIPv4,
            proxyPort: model.store.proxyPort,
            proxyEnabled: model.store.proxyEnabled && model.proxyRunning
        )
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

/// Menu-item press: a light wash on pointer-down, not the default macOS blue highlight.
private struct MenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
