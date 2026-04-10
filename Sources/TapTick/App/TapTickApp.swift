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
    let utilities = UtilitiesController()
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
    /// The app that was frontmost when the settings window was last shown via the toggle hotkey.
    /// Restored on toggle-close so the user lands back where they started.
    private var previousActiveApp: NSRunningApplication?

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

        appState.utilities.onReservedHotkeysChanged = { [weak hotkeyService = appState.hotkeyService, weak store = appState.store] in
            guard let hotkeyService, let store else { return }
            hotkeyService.restart(store: store)
        }
        appState.utilities.bootstrap()
        appState.hotkeyService.start(
            store: appState.store,
            utilities: appState.utilities
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
            openSettingsWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = currentSettingsWindow() {
            // Window already exists (ordered-out or behind another app): bring it directly
            // to front via AppKit. This is synchronous and happens after activate(), so the
            // window reliably appears on the first keypress — no deferred Combine/SwiftUI hop.
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window hasn't been created yet (first launch after suppressed startup).
            // Delegate to the SwiftUI scene mechanism to instantiate it.
            AppState.shared.openSettingsTrigger += 1
        }
    }

    private func toggleSettingsWindow() {
        // Only collapse the window when it is already the key window and the app is active
        // (i.e. the user is actively looking at it). If the window is merely visible but
        // behind another app, the first press should bring it to front, not close it.
        if let window = currentSettingsWindow(), window.isVisible, window.isKeyWindow {
            // orderOut instead of close keeps the NSWindow instance alive so the next
            // open can use makeKeyAndOrderFront directly without the SwiftUI scene hop.
            window.orderOut(nil)
            // Restore focus to wherever the user was before we took it.
            // Guard against restoring to TapTick itself (no visible window would remain).
            let app = previousActiveApp
            previousActiveApp = nil
            if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                app?.activate()
            }
            return
        }

        // Carbon delivers the hotkey without activating TapTick, so frontmostApplication
        // is still the user's previous app at this point — capture it before activate().
        previousActiveApp = NSWorkspace.shared.frontmostApplication
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
                .environment(appState.utilities)
                .environment(appState.hotkeyService)
                .environment(appState.loginItemManager)
                .environment(appState.cloudSync)
                .environment(appState.updateService)
                .background(SettingsWindowObserver { window in
                    guard let window else { return }
                    window.identifier = settingsWindowIdentifier
                    window.styleMask.remove(.resizable)
                    appState.settingsWindow = window
                })
                .frame(minWidth: 980, idealWidth: 980, maxWidth: 980,
                       minHeight: 600, idealHeight: 600, maxHeight: 600)
        }
        .windowResizability(.contentSize)
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
