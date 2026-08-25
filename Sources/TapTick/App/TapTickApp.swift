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
    let scriptLogStore: ScriptLogStore
    let scriptOutputPresenter: ScriptOutputPresenter
    let shortcutExecutor: ShortcutExecutor
    let menuBarTextController: MenuBarTextController

    /// Native NSStatusItem + NSMenu controller — retained for the lifetime of the app.
    var menuBarController: MenuBarController?

    private init() {
        let sync = CloudSyncService()
        self.cloudSync = sync
        let store = ShortcutStore(cloudSync: sync)
        let scriptLogStore = ScriptLogStore()
        let scriptOutputPresenter = ScriptOutputPresenter()
        self.store = store
        self.scriptLogStore = scriptLogStore
        self.scriptOutputPresenter = scriptOutputPresenter
        self.shortcutExecutor = ShortcutExecutor(
            store: store,
            logStore: scriptLogStore,
            outputPresenter: scriptOutputPresenter
        )
        self.menuBarTextController = MenuBarTextController(store: store)
    }
}

/// Returns `true` only when the launch Apple Event identifies this as a login-item launch.
/// Parent-process inspection is not reliable because LaunchServices may also launch a manually
/// opened UIElement app through launchd.
private func isLaunchedByLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
    return event.eventID == kAEOpenApplication
        && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
}

/// Owns app-level presentation: Settings window lifecycle, focus handoff, and Dock policy.
/// Keeping these decisions together prevents individual views and entry points from creating
/// different activation behavior for the same window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsNotificationObserver: Any?
    private var toggleSettingsNotificationObserver: Any?
    private var settingsWindowCloseObserver: Any?
    private var workspaceActivationObserver: Any?
    private var defaultsObserver: Any?
    private weak var observedSettingsWindow: NSWindow?
    private var lastExternalActiveApp: NSRunningApplication?
    private var appliedDockIconVisibility: Bool?
    private var isReadyForActivationPresentation = false
    private var isSettingsPresentationPending = false
    private var isTerminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        startTrackingExternalActivation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState.shared
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let shouldOpenSettings = !hasLaunchedBefore || !isLaunchedByLoginItem()

        UserDefaults.standard.register(defaults: ["showDockIcon": false])

        if !hasLaunchedBefore {
            // First launch: apply defaults and register login item
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            // Enable launch at login by default on first launch
            try? SMAppService.mainApp.register()
        }

        applyDockIconPolicyFromDefaults()
        startObservingDockIconPreference()

        // Install the native menu bar controller now that NSApplication is fully initialised.
        appState.menuBarController = MenuBarController(
            store: appState.store,
            shortcutExecutor: appState.shortcutExecutor,
            updateService: appState.updateService,
            menuBarTextController: appState.menuBarTextController
        )
        appState.menuBarTextController.bootstrap()

        appState.utilities.onReservedHotkeysChanged = {
            [weak hotkeyService = appState.hotkeyService, weak store = appState.store] in
            guard let hotkeyService, let store else { return }
            hotkeyService.restart(store: store)
        }
        appState.utilities.bootstrap()

        appState.hotkeyService.onShortcutTriggered = {
            [weak shortcutExecutor = appState.shortcutExecutor] shortcutID in
            shortcutExecutor?.execute(shortcutID: shortcutID)
        }

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

        isReadyForActivationPresentation = true
        if shouldOpenSettings {
            // Manual and first launches present Settings. Login-item launches remain quiet.
            openSettingsWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard isReadyForActivationPresentation else { return }

        if let settingsWindow = currentSettingsWindow(),
            settingsWindow.isVisible || settingsWindow.isMiniaturized
        {
            return
        }
        guard !hasVisibleInteractiveWindow() else { return }

        openSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        removeObservers()
    }

    func registerSettingsWindow(_ window: NSWindow) {
        window.identifier = settingsWindowIdentifier
        window.styleMask.remove(.resizable)
        // The automatic style changes with the active detail pane's scrolling context.
        // Settings has a persistent header, so its boundary must be a window-level invariant.
        window.titlebarSeparatorStyle = .line
        AppState.shared.settingsWindow = window
        isSettingsPresentationPending = false

        guard observedSettingsWindow !== window else { return }

        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }

        observedSettingsWindow = window
        settingsWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let window else { return }
                self?.settingsWindowWillClose(window)
            }
        }
    }

    func dismissSettingsWindow() {
        guard let window = currentSettingsWindow(), window.isVisible else {
            return
        }

        // Keep the window alive for a synchronous reopen, then return to the user's work.
        window.orderOut(nil)
        handOffFocusIfNeeded(excluding: window)
    }

    private func openSettingsWindow() {
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)
        NSApp.unhide(nil)
        if !NSApp.isActive {
            NSApp.activate()
        }

        if let window = currentSettingsWindow() {
            isSettingsPresentationPending = false
            window.makeKeyAndOrderFront(nil)
        } else if !isSettingsPresentationPending {
            isSettingsPresentationPending = true
            AppState.shared.openSettingsTrigger += 1
        }
    }

    private func toggleSettingsWindow() {
        // Only collapse the window when it is already the key window and the app is active
        // (i.e. the user is actively looking at it). If the window is merely visible but
        // behind another app, the first press should bring it to front, not close it.
        if let window = currentSettingsWindow(), window.isVisible, window.isKeyWindow {
            dismissSettingsWindow()
            return
        }

        openSettingsWindow()
    }

    private func settingsWindowWillClose(_ window: NSWindow) {
        guard observedSettingsWindow === window else { return }

        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
            self.settingsWindowCloseObserver = nil
        }
        AppState.shared.settingsWindow = nil
        observedSettingsWindow = nil
        isSettingsPresentationPending = false
        handOffFocusIfNeeded(excluding: window)
    }

    private func handOffFocusIfNeeded(excluding settingsWindow: NSWindow) {
        guard !isTerminating, NSApp.isActive else { return }
        guard !hasVisibleInteractiveWindow(excluding: settingsWindow) else { return }

        guard let target = lastExternalActiveApp, !target.isTerminated else {
            // A cold launch may not have observed the previously active process. Hiding lets
            // macOS select the appropriate successor without leaving TapTick active and empty.
            NSApp.hide(nil)
            return
        }

        NSApp.yieldActivation(to: target)
        target.activate()
    }

    private func hasVisibleInteractiveWindow(excluding excludedWindow: NSWindow? = nil) -> Bool {
        NSApp.windows.contains { window in
            if let excludedWindow, window === excludedWindow { return false }
            return window.isVisible
                && window.canBecomeKey
                && !window.styleMask.contains(.nonactivatingPanel)
        }
    }

    private func startTrackingExternalActivation() {
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app =
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.rememberExternalApp(app)
            }
        }
    }

    private func rememberExternalApp(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        lastExternalActiveApp = app
    }

    private func startObservingDockIconPreference() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyDockIconPolicyFromDefaults()
            }
        }
    }

    private func applyDockIconPolicyFromDefaults() {
        let isVisible = UserDefaults.standard.bool(forKey: "showDockIcon")
        guard appliedDockIconVisibility != isVisible else { return }
        appliedDockIconVisibility = isVisible

        let settingsWindow = currentSettingsWindow()
        let shouldRestoreSettingsFocus = settingsWindow?.isKeyWindow == true
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)

        guard shouldRestoreSettingsFocus else { return }
        Task { @MainActor [weak settingsWindow] in
            await Task.yield()
            NSApp.activate()
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        [
            settingsNotificationObserver, toggleSettingsNotificationObserver,
            settingsWindowCloseObserver, defaultsObserver,
        ]
        .compactMap { $0 }
        .forEach(center.removeObserver)

        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }

        settingsNotificationObserver = nil
        toggleSettingsNotificationObserver = nil
        settingsWindowCloseObserver = nil
        workspaceActivationObserver = nil
        defaultsObserver = nil
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
                .environment(appState.scriptLogStore)
                .environment(appState.shortcutExecutor)
                .environment(appState.menuBarTextController)
                .background(
                    SettingsWindowEscapeShortcut {
                        appDelegate.dismissSettingsWindow()
                    }
                )
                .background(
                    SettingsWindowObserver { window in
                        guard let window else { return }
                        appDelegate.registerSettingsWindow(window)
                    }
                )
                .frame(
                    minWidth: 980, idealWidth: 980, maxWidth: 980,
                    minHeight: 600, idealHeight: 600, maxHeight: 600)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultLaunchBehavior(.suppressed)
        .onChange(of: appState.openSettingsTrigger) {
            openWindow(id: "settings")
        }
        .commands {
            TextEditingCommands()

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

private struct SettingsWindowEscapeShortcut: View {
    let onDismiss: () -> Void

    var body: some View {
        Button("Dismiss Settings", action: onDismiss)
            .keyboardShortcut(.cancelAction)
            .labelsHidden()
            .frame(width: 0, height: 0)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

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
