import SwiftUI

@main
struct LanternApp: App {
    @State private var model = AppModel()
    @State private var updater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(model)
                .frame(width: LanternTheme.panelWidth)
                .frame(height: panelHeight)
                .animation(.spring(response: 0.34, dampingFraction: 0.9), value: panelHeight)
        } label: {
            MenuBarLabel(tint: model.statusTint)
                .task {
                    model.start()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Lantern Settings", id: "settings") {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 480)
    }

    private var panelHeight: CGFloat {
        if model.showingAddSheet || !model.store.aliases.isEmpty {
            return LanternTheme.panelExpandedHeight
        }
        return LanternTheme.panelHomeHeight
    }
}

private struct MenuBarLabel: View {
    let tint: AppModel.StatusTint

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .foregroundStyle(color)
            .accessibilityLabel("Lantern")
    }

    private var color: Color {
        switch tint {
        case .live: return LanternTheme.live
        case .pending: return LanternTheme.pending
        case .error: return LanternTheme.danger
        case .idle: return .primary
        }
    }
}
