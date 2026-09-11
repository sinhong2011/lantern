import AppKit
import SwiftUI

struct MenuPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var copiedLanIP = false
    @State private var networkChipHover = false

    var body: some View {
        Group {
            if model.showingAddSheet {
                AddServiceSheet()
                    .environment(model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                homePanel
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(width: LanternTheme.panelWidth - LanternTheme.panelPadding * 2, alignment: .top)
        .padding(LanternTheme.panelPadding)
        .frame(width: LanternTheme.panelWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let toast = model.toastMessage {
                toastBanner(toast)
                    .padding(.horizontal, LanternTheme.panelPadding)
                    .padding(.bottom, 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toastMessage)
        .animation(.easeOut(duration: 0.16), value: model.showingAddSheet)
        .lanternPanelBackground()
        .onAppear {
            model.start()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .onChange(of: model.network.lanIPv4) { _, _ in
            model.scheduleReconcile()
        }
    }

    private var homePanel: some View {
        VStack(spacing: 10) {
            header

            if let error = model.lastError {
                errorBanner(error)
            }

            if model.store.aliases.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.store.aliases) { alias in
                            ServiceRowView(alias: alias)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            footer
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lantern")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                networkChip
            }

            Spacer(minLength: 8)

            Toggle("Broadcast", isOn: Binding(
                get: { model.store.masterBroadcastEnabled },
                set: { model.setMasterBroadcast($0) }
            ))
            .toggleStyle(BroadcastBeaconStyle())
            .labelsHidden()
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var networkChip: some View {
        let ip = model.network.lanIPv4
        let canCopy = ip != nil
        return Button {
            guard model.copyLanIP() != nil else { return }
            copiedLanIP = true
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                copiedLanIP = false
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copiedLanIP ? "checkmark" : model.network.linkKind.symbolName)
                    .font(.system(size: 8.5, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .frame(width: 12)

                if copiedLanIP {
                    Text("Copied")
                        .font(.system(size: 10.5, weight: .medium))
                } else if let ip {
                    Text(ip)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                    if let name = model.network.interfaceName {
                        Text(name)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                } else {
                    Text(model.network.statusLabel)
                        .font(.system(size: 10.5, weight: .medium))
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                Color.primary.opacity(networkChipHover && canCopy ? 0.11 : 0.06),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!canCopy)
        .onHover { networkChipHover = $0 }
        .help(canCopy ? "Copy LAN address" : model.network.statusLabel)
        .accessibilityLabel(ip.map { "LAN address \($0)" } ?? model.network.statusLabel)
        .accessibilityHint(canCopy ? "Copies the address" : "")
        .animation(.easeOut(duration: 0.12), value: copiedLanIP)
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if model.canSuggestAlternateProxyPort {
                Button("Keep sharing without port 80") {
                    model.useAlternateProxyPort(8787)
                }
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(LanternTheme.danger)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LanternTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: LanternTheme.radiusM, style: .continuous))
    }

    private var emptyState: some View {
        LanternSection {
            VStack(alignment: .leading, spacing: 2) {
                Text("No Services")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                Text("Share a local app as a short name on your Wi‑Fi.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)

                LanternPrimaryButton(title: "Add Service…") {
                    model.beginAdd()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)

                LanternMenuRow(title: "Use example web → 8080", symbol: "sparkles", chevron: false) {
                    model.addSampleWebService()
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: dotColor.opacity(pulse && model.statusTint == .live && !reduceMotion ? 0.55 : 0), radius: 3)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.beginAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Add service")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Lantern")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func toastBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var dotColor: Color {
        switch model.statusTint {
        case .live: return LanternTheme.live
        case .pending: return LanternTheme.pending
        case .error: return LanternTheme.danger
        case .idle: return Color.secondary.opacity(0.4)
        }
    }

    private var statusText: String {
        switch model.statusTint {
        case .live:
            if model.store.proxyEnabled && model.proxyRunning && model.store.proxyPort != 80 {
                return "Broadcasting · \(LanternTheme.portText(model.store.proxyPort))"
            }
            return "Broadcasting"
        case .pending: return "Waiting for LAN"
        case .error: return "Needs attention"
        case .idle: return "Idle"
        }
    }
}
