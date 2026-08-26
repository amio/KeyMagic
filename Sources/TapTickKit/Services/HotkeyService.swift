import Foundation
import Carbon.HIToolbox
import Observation

/// Manages global hotkey registration using Carbon's RegisterEventHotKey API.
///
/// This approach is sandbox-compatible and requires no Accessibility permission.
/// Instead of intercepting the entire keyboard event stream, each KeyCombo is
/// registered individually with the system; macOS delivers a targeted callback
/// only when that exact combination is pressed.
@Observable
@MainActor
public final class HotkeyService {
    public init() {}

    private(set) var isListening = false
    private(set) var settingsWindowHotkey = HotkeyService.loadSettingsWindowHotkey()

    /// Active registrations keyed by the Carbon hot-key ID (sequential UInt32).
    private var registrations: [UInt32: Registration] = [:]
    /// Monotonically increasing ID counter for Carbon hot-key handles.
    private var nextID: UInt32 = 1
    /// Nested recorders can temporarily suspend global hotkeys without racing each other.
    private var suspensionCount = 0

    private var store: ShortcutStore?
    private var utilities: UtilitiesController?
    private var eventHandlerRef: EventHandlerRef?

    /// Delivers a registered user-shortcut ID to the process-lifetime execution owner.
    public var onShortcutTriggered: (@MainActor @Sendable (UUID) -> Void)?

    static let settingsWindowHotkeyDefaultsKey = "settingsWindowHotkey"
    static let defaultSettingsWindowHotkey = KeyCombo(
        keyCode: UInt32(kVK_ANSI_Comma),
        modifiers: [.command, .control, .option]
    )

    // MARK: - Public API

    /// Register all shortcuts in the store and begin dispatching.
    public func start(store: ShortcutStore, utilities: UtilitiesController? = nil) {
        self.store = store
        if let utilities {
            self.utilities = utilities
        }
        rebuildRegistrations(store: store)
    }

    /// Unregister all hotkeys and stop dispatching.
    public func stop() {
        unregisterAllHotKeys()
        isListening = false
    }

    /// Re-register all hotkeys (call after shortcuts change).
    public func restart(store: ShortcutStore) {
        stop()
        start(store: store)
    }

    /// Returns true when a combo conflicts with either a user shortcut or the reserved settings hotkey.
    func hasConflict(
        keyCombo: KeyCombo,
        excludingShortcutID: UUID? = nil,
        excludingSettingsWindowHotkey: Bool = false,
        excludingUtilityID: UtilityID? = nil
    ) -> Bool {
        let shortcutConflict = store?.hasConflict(keyCombo: keyCombo, excludingID: excludingShortcutID) ?? false
        let settingsConflict = !excludingSettingsWindowHotkey && settingsWindowHotkey == keyCombo
        let utilityConflict =
            utilities?.reservedHotkeyConflict(
                for: keyCombo,
                excluding: excludingUtilityID
            ) ?? false
        return shortcutConflict || settingsConflict || utilityConflict
    }

    /// Persist a new settings-window hotkey and rebuild registrations if needed.
    func updateSettingsWindowHotkey(_ combo: KeyCombo) {
        settingsWindowHotkey = combo
        saveSettingsWindowHotkey(combo)
        rebuildActiveRegistrationsIfPossible()
    }

    /// Restore the reserved settings-window hotkey to the app default.
    func restoreDefaultSettingsWindowHotkey() {
        updateSettingsWindowHotkey(Self.defaultSettingsWindowHotkey)
    }

    /// Temporarily unregister all global hotkeys while a recorder is active.
    func suspendRegistrations() {
        suspensionCount += 1
        guard suspensionCount == 1 else { return }
        unregisterAllHotKeys()
        isListening = eventHandlerRef != nil
    }

    /// Re-register hotkeys after the last active recorder stops.
    func resumeRegistrations() {
        guard suspensionCount > 0 else { return }
        suspensionCount -= 1
        guard suspensionCount == 0 else { return }
        rebuildActiveRegistrationsIfPossible()
    }

    // MARK: - Registration

    private func rebuildRegistrations(store: ShortcutStore) {
        unregisterAllHotKeys()

        installEventHandlerIfNeeded()

        guard suspensionCount == 0 else {
            isListening = eventHandlerRef != nil
            return
        }

        var registeredCombos = Set<KeyCombo>()

        registerCombo(
            settingsWindowHotkey,
            action: .toggleSettingsWindow,
            registeredCombos: &registeredCombos
        )

        for utilityHotkey in utilities?.reservedHotkeys() ?? [] {
            registerCombo(
                utilityHotkey.combo,
                action: .toggleUtility(utilityHotkey.featureID, utilityHotkey.action),
                registeredCombos: &registeredCombos
            )
        }

        for shortcut in store.shortcuts where shortcut.isEnabled {
            guard let combo = shortcut.keyCombo else { continue }
            registerCombo(
                combo,
                action: .shortcut(shortcut.id),
                registeredCombos: &registeredCombos
            )
        }

        // Listening is considered active as long as the handler is installed,
        // even if there are currently no shortcuts to register.
        isListening = eventHandlerRef != nil
    }

    private func registerCombo(
        _ combo: KeyCombo,
        action: RegistrationAction,
        registeredCombos: inout Set<KeyCombo>
    ) {
        guard registeredCombos.insert(combo).inserted else { return }

        let id = nextID
        nextID += 1

        let eventHotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers.carbonModifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return }
        registrations[id] = Registration(ref: ref, action: action)
    }

    // MARK: - Carbon Event Handler

    /// Install the application-level Carbon event handler (idempotent).
    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            userInfo,
            &eventHandlerRef
        )
    }

    // MARK: - Dispatch

    /// Called by the C-level event handler when a registered hotkey fires.
    fileprivate func handleHotKeyEvent(id: UInt32) {
        guard let registration = registrations[id] else { return }

        switch registration.action {
        case .shortcut(let shortcutID):
            guard let store,
                store.shortcuts.contains(where: { $0.id == shortcutID })
            else { return }

            onShortcutTriggered?(shortcutID)

        case .toggleSettingsWindow:
            NotificationCenter.default.post(name: .toggleSettingsWindow, object: nil)

        case .toggleUtility(let featureID, let action):
            utilities?.handleHotkey(for: featureID, action: action)
        }
    }

    private func rebuildActiveRegistrationsIfPossible() {
        guard let store else { return }
        rebuildRegistrations(store: store)
    }

    private func unregisterAllHotKeys() {
        registrations.values.forEach { UnregisterEventHotKey($0.ref) }
        registrations.removeAll()
    }

    private static func loadSettingsWindowHotkey() -> KeyCombo {
        guard let data = UserDefaults.standard.data(forKey: settingsWindowHotkeyDefaultsKey),
            let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else {
            return defaultSettingsWindowHotkey
        }

        return combo
    }

    private func saveSettingsWindowHotkey(_ combo: KeyCombo) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsWindowHotkeyDefaultsKey)
    }
}

// MARK: - Supporting Types

/// Associates a Carbon EventHotKeyRef with a Shortcut UUID.
private struct Registration {
    let ref: EventHotKeyRef
    let action: RegistrationAction
}

/// Identifies what a registered Carbon hotkey should do when it fires.
private enum RegistrationAction {
    case shortcut(Shortcut.ID)
    case toggleSettingsWindow
    case toggleUtility(UtilityID, String)
}

/// Four-char code used to namespace our hot-key IDs within the system.
/// 'TTgc' — TapTick global combos.
private let hotKeySignature: OSType = 0x5454_6763

// MARK: - Carbon Event Handler (C function pointer)

private func hotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        service.handleHotKeyEvent(id: hotKeyID.id)
    }

    return noErr
}
