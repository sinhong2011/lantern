import AppKit
import SwiftUI

struct MenuPanelView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Group {
            if model.showingAddSheet {
                AddServiceSheet()
                    .environment(model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                homePanel
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let toast = model.toastMessage {
                toastBanner(toast)
                    .padding(.horizontal, 12)
                    .padding(.bottom, model.showingAddSheet ? 10 : 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.toastMessage)
        .animation(.easeOut(duration: 0.2), value: model.showingAddSheet)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.start()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .onChange(of: model.network.lanIPv4) { _, _ in
            Task { await model.reconcile() }
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
                    LazyVStack(spacing: 10) {
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
        LanternSection {
            HStack(spacing: 10) {
                Image(systemName: "light.min")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LanternTheme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Lantern")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.network.statusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: Binding(
                    get: { model.store.masterBroadcastEnabled },
                    set: { model.setMasterBroadcast($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(LanternTheme.accent)
                .accessibilityLabel("Broadcast")
                .help(model.store.masterBroadcastEnabled ? "Broadcasting on LAN" : "Broadcast off")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if model.canSuggestAlternateProxyPort {
                Button("Use backup link style (:8787)") {
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

            Menu {
                Button("Quit Lantern", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More")
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
