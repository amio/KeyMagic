import AppKit
import ServiceManagement
import SwiftUI
import TapTickKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var openSettingsTrigger = 0
    weak var settingsWindow: NSWindow?

    // MARK: - Shared Services

    let cloudSync: CloudSyncService
    let store: ShortcutStore
    let builtInFeatures = BuiltInFeatureController()
    let hotkeyService = HotkeyService()
    let loginItemManager = LoginItemManager()
    let updateService = UpdateService()

    /// Native NSStatusItem + NSMenu controller — retained for the lifetime of the app.
    var menuBarController: MenuBarController?

    private init() {
        let sync = CloudSyncService()
        self.cloudSync = sync
        self.store = ShortcutStore(cloudSync: sync)
    }
}

/// Returns `true` when this process was launched by launchd (login item / system boot),
/// rather than directly by the user (Dock, Finder, Terminal, etc.).
///
/// The heuristic compares the parent-process name: launchd always has PID 1 and name
/// "launchd". Any interactive launch will have a parent such as "Dock" or "launchservicesd".
private func isLaunchedByLoginItem() -> Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getppid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let parentName = withUnsafeBytes(of: info.kp_proc.p_comm) { bytes in
        bytes.baseAddress.flatMap { String(validatingCString: $0.assumingMemoryBound(to: CChar.self)) } ?? ""
    }
    return parentName == "launchd"
}

/// Applies the dock icon policy once at launch based on the stored user preference.
/// Using an app delegate avoids the crash from accessing `NSApp` in the `App.init()`,
/// where `NSApplication.shared` has not yet been created.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Observation token for the notification posted by `MenuBarController` to open settings.
    private var settingsNotificationObserver: Any?
    private var toggleSettingsNotificationObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState.shared
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

        if !hasLaunchedBefore {
            // First launch: apply defaults and register login item
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            // showDockIcon defaults to true — no write needed; @AppStorage default handles UI,
            // but AppDelegate reads UserDefaults directly, so seed the value explicitly.
            if UserDefaults.standard.object(forKey: "showDockIcon") == nil {
                UserDefaults.standard.set(true, forKey: "showDockIcon")
            }
            // Enable launch at login by default on first launch
            try? SMAppService.mainApp.register()

            NSApp.activate(ignoringOtherApps: true)
        } else {
            let launchedBySystem = isLaunchedByLoginItem()

            if !launchedBySystem {
                // Launched manually by the user: open settings window and bring app to front.
                // Window uses .defaultLaunchBehavior(.suppressed) so it won't open automatically.
                appState.openSettingsTrigger += 1
                NSApp.activate(ignoringOtherApps: true)
            }
            // Launched by login item: do nothing — window stays hidden, app lives in menu bar.
        }

        let showDockIcon = UserDefaults.standard.bool(forKey: "showDockIcon")
        if !showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }

        // Install the native menu bar controller now that NSApplication is fully initialised.
        appState.menuBarController = MenuBarController(
            store: appState.store,
            hotkeyService: appState.hotkeyService,
            updateService: appState.updateService
        )

        appState.builtInFeatures.onReservedHotkeysChanged = { [weak hotkeyService = appState.hotkeyService, weak store = appState.store] in
            guard let hotkeyService, let store else { return }
            hotkeyService.restart(store: store)
        }
        appState.builtInFeatures.bootstrap()
        appState.hotkeyService.start(
            store: appState.store,
            builtInFeatures: appState.builtInFeatures
        )

        // Listen for the "open settings" notification posted by MenuBarController.
        settingsNotificationObserver = NotificationCenter.default.addObserver(
            forName: .openSettingsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openSettingsWindow()
            }
        }

        toggleSettingsNotificationObserver = NotificationCenter.default.addObserver(
            forName: .toggleSettingsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.toggleSettingsWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppState.shared.openSettingsTrigger += 1
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func openSettingsWindow() {
        AppState.shared.openSettingsTrigger += 1
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleSettingsWindow() {
        if let window = currentSettingsWindow(), window.isVisible {
            window.close()
            return
        }

        openSettingsWindow()
    }

    private func currentSettingsWindow() -> NSWindow? {
        AppState.shared.settingsWindow
            ?? NSApp.windows.first(where: { $0.identifier == settingsWindowIdentifier })
    }
}

/// TapTick — a utility app for launching apps and running scripts via global hotkeys.
///
/// Architecture:
/// - The app lives primarily in the menu bar (native NSStatusItem + NSMenu via MenuBarController).
/// - A settings window is the main (and only) substantial UI.
/// - Global keyboard shortcuts are registered via Carbon's RegisterEventHotKey (no permissions needed).
/// - Login item is managed through ServiceManagement.
/// - Shortcuts are optionally synced across Macs via iCloud Drive.
@main
struct TapTickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // MARK: - Settings Window
        Window("TapTick Settings", id: "settings") {
            SettingsView()
                .environment(appState.store)
                .environment(appState.builtInFeatures)
                .environment(appState.hotkeyService)
                .environment(appState.loginItemManager)
                .environment(appState.cloudSync)
                .environment(appState.updateService)
                .background(SettingsWindowObserver { window in
                    guard let window else { return }
                    window.identifier = settingsWindowIdentifier
                    appState.settingsWindow = window
                })
                .frame(minWidth: 890, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .onChange(of: appState.openSettingsTrigger) {
            openWindow(id: "settings")
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appState.updateService.checkForUpdates()
                }
                .disabled(!appState.updateService.canCheckForUpdates)
            }
        }
    }
}

private let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("TapTick.settingsWindow")

/// Captures the underlying NSWindow for the SwiftUI settings scene once it exists.
private struct SettingsWindowObserver: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        let view = SettingsWindowObserverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindow()
    }
}

private final class SettingsWindowObserverView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveWindow()
    }

    func resolveWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.onResolve?(self?.window)
        }
    }
}
