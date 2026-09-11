import AppKit
import Observation
import Sparkle

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var display: String {
        marketing == build ? marketing : "\(marketing) (\(build))"
    }
}

/// Sparkle updater for the menu-bar (LSUIElement) app.
/// The user-driver delegate is retained here because Sparkle holds it weakly.
@MainActor
@Observable
final class AppUpdater {
    private let presenter = UpdatePresenter()
    private let controller: SPUStandardUpdaterController

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: presenter
        )
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

private final class UpdatePresenter: NSObject, SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
