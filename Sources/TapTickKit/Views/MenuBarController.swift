import AppKit

/// Manages the menu bar status item with a native `NSMenu`.
///
/// Replaces the SwiftUI `MenuBarExtra` with a real `NSStatusItem` + `NSMenu` that provides:
/// - Native key equivalent glyphs (⌘⌥⌃⇧+key) rendered by AppKit
/// - Standard keyboard navigation and VoiceOver support
/// - Observation-driven rebuild when `ShortcutStore.shortcuts` changes
/// - Dynamic show/hide via UserDefaults KVO for `"showMenuBarIcon"`
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private let store: ShortcutStore
    private let hotkeyService: HotkeyService
    private let updateService: UpdateService

    /// Watches `"showMenuBarIcon"` in UserDefaults via KVO.
    private var visibilityObservation: NSKeyValueObservation?

    /// Tracks the Observation framework subscription so we can cancel on deinit.
    private var observationTask: Task<Void, Never>?

    /// Tag used to identify the "Check for Updates…" item for dynamic enable/disable.
    private static let updateMenuItemTag = 999

    public init(
        store: ShortcutStore,
        hotkeyService: HotkeyService,
        updateService: UpdateService
    ) {
        self.store = store
        self.hotkeyService = hotkeyService
        self.updateService = updateService
        super.init()

        // Seed default if not yet set — matches GeneralSettingsView's @AppStorage default.
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])

        // Apply initial visibility, then observe changes.
        applyVisibility(UserDefaults.standard.bool(forKey: "showMenuBarIcon"))

        visibilityObservation = UserDefaults.standard.observe(
            \.showMenuBarIcon,
            options: [.new]
        ) { [weak self] _, change in
            guard let visible = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.applyVisibility(visible)
            }
        }

        startObservingStore()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Visibility

    private func applyVisibility(_ visible: Bool) {
        if visible {
            installStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "keyboard.badge.ellipsis",
                accessibilityDescription: "TapTick"
            )
        }
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - Observation

    /// Re-builds the menu whenever `store.shortcuts` changes, using Swift Observation.
    ///
    /// Uses `withObservationTracking` + `AsyncStream` so the task genuinely suspends
    /// until a tracked property mutates, instead of polling.
    private func startObservingStore() {
        observationTask = Task { [weak self] in
            // Build an initial menu synchronously on the first pass,
            // then wait for each mutation before rebuilding.
            while !Task.isCancelled {
                guard let self else { return }

                // Suspend until Observation detects a change to `store.shortcuts`.
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        // Touch the shortcuts array so Observation records the access.
                        _ = self.store.shortcuts
                    } onChange: {
                        // Called exactly once, on an arbitrary thread, when the
                        // tracked property mutates. Resume the suspended task.
                        continuation.resume()
                    }
                }

                guard !Task.isCancelled else { return }

                // Small sleep to coalesce rapid-fire changes (e.g. bulk import).
                try? await Task.sleep(for: .milliseconds(50))

                guard !Task.isCancelled else { return }
                self.rebuildMenu()
            }
        }
    }

    private func rebuildMenu() {
        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// Refresh dynamic state (e.g. update button enabled) every time the menu opens.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        if let updateItem = menu.item(withTag: Self.updateMenuItemTag) {
            updateItem.isEnabled = updateService.canCheckForUpdates
        }
    }

    // MARK: - Menu Construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let appShortcuts = store.shortcuts.filter { $0.isEnabled && $0.action.isLaunchApp }
        let scriptShortcuts = store.shortcuts.filter { $0.isEnabled && !$0.action.isLaunchApp }
        let hasApps = !appShortcuts.isEmpty
        let hasScripts = !scriptShortcuts.isEmpty

        if !hasApps && !hasScripts {
            let empty = NSMenuItem(title: "No shortcuts configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for shortcut in appShortcuts {
                menu.addItem(menuItem(for: shortcut))
            }
            if hasApps && hasScripts {
                menu.addItem(.separator())
            }
            for shortcut in scriptShortcuts {
                menu.addItem(menuItem(for: shortcut))
            }
        }

        menu.addItem(.separator())

        // Check for Updates…
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.tag = Self.updateMenuItemTag
        updateItem.isEnabled = updateService.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // Settings…
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit TapTick",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// Build an `NSMenuItem` for a single shortcut, with its app icon and native key equivalent glyph.
    private func menuItem(for shortcut: Shortcut) -> NSMenuItem {
        let keyEquiv: String
        var modMask: NSEvent.ModifierFlags = []

        if let combo = shortcut.keyCombo {
            keyEquiv = combo.menuItemKeyEquivalent
            modMask = combo.menuItemModifierMask
        } else {
            keyEquiv = ""
        }

        let item = NSMenuItem(
            title: shortcut.name,
            action: #selector(triggerShortcut(_:)),
            keyEquivalent: keyEquiv
        )
        item.keyEquivalentModifierMask = modMask
        item.target = self
        item.representedObject = shortcut.id
        item.image = icon(for: shortcut.action)

        return item
    }

    /// Resolve an appropriately-sized icon for the shortcut's action type.
    private func icon(for action: ShortcutAction) -> NSImage? {
        let size = NSSize(width: 18, height: 18)

        switch action {
        case .launchApp(let bundleID, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return symbolImage("app", size: size)
            }
            let appIcon = NSWorkspace.shared.icon(forFile: url.path)
            appIcon.size = size
            return appIcon

        case .runScript:
            return symbolImage("terminal", size: size)

        case .runScriptFile:
            return symbolImage("doc.text", size: size)
        }
    }

    /// Create a template SF Symbol image at the given point size.
    private func symbolImage(_ name: String, size: NSSize) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.size = size
        configured.isTemplate = true
        return configured
    }

    // MARK: - Actions

    @objc private func triggerShortcut(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let shortcut = store.shortcuts.first(where: { $0.id == id })
        else { return }
        hotkeyService.trigger(shortcut: shortcut, store: store)
    }

    @objc private func checkForUpdates() {
        updateService.checkForUpdates()
    }

    @objc private func openSettings() {
        // Post a notification that TapTickApp's AppDelegate picks up to open the settings window.
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Name

public extension Notification.Name {
    /// Posted by `MenuBarController` when the user clicks "Settings…" in the menu bar dropdown.
    static let openSettingsWindow = Notification.Name("TapTick.openSettingsWindow")
}

// MARK: - UserDefaults KVO Key Path

/// Expose `"showMenuBarIcon"` as an `@objc dynamic` property so `NSKeyValueObservation` works.
extension UserDefaults {
    @objc dynamic var showMenuBarIcon: Bool {
        bool(forKey: "showMenuBarIcon")
    }
}