import Carbon.HIToolbox
import Foundation
import Testing
@testable import TapTickKit

@Suite("HotkeyService")
struct HotkeyServiceTests {
    @Test("Uses the default settings window hotkey when no override is stored")
    @MainActor
    func defaultSettingsWindowHotkey() {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        defaults.removeObject(forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        defer {
            restore(previous, in: defaults)
        }

        let service = HotkeyService()
        #expect(service.settingsWindowHotkey == HotkeyService.defaultSettingsWindowHotkey)
    }

    @Test("Persists settings window hotkey overrides")
    @MainActor
    func persistsSettingsWindowHotkeyOverride() {
        let defaults = UserDefaults.standard
        let previous = defaults.data(forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        defer {
            restore(previous, in: defaults)
        }

        let override = KeyCombo(
            keyCode: UInt32(kVK_ANSI_Slash),
            modifiers: [.command, .control, .option]
        )

        let service = HotkeyService()
        service.updateSettingsWindowHotkey(override)

        let reloaded = HotkeyService()
        #expect(service.settingsWindowHotkey == override)
        #expect(reloaded.settingsWindowHotkey == override)
    }

    @Test("Utility hotkeys participate in conflict detection")
    @MainActor
    func utilityHotkeyConflicts() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickHotkeyService-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let utilities = UtilitiesController(directory: directory)
        let service = HotkeyService()

        service.start(store: store, utilities: utilities)
        defer { service.stop() }

        let reservedHotkey = utilities.keystrokeOverlay.hotkey
        #expect(service.hasConflict(keyCombo: reservedHotkey))
        #expect(
            service.hasConflict(
                keyCombo: reservedHotkey,
                excludingUtilityID: .keystrokeOverlay
            ) == false
        )
    }

    @Test("Direct shortcut triggers use the script completion pipeline")
    @MainActor
    func directTriggerRunsAndRecordsLikeAHotkey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickHotkeyService-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let logStore = ScriptLogStore(directory: directory)
        let shortcut = Shortcut(
            name: "Trigger Test",
            action: .runScript(script: "sleep 0.02; printf trigger", shell: .sh)
        )
        store.add(shortcut)

        let service = HotkeyService()
        service.onScriptCompleted = { [logStore] log in
            logStore.record(log)
        }
        service.trigger(shortcut: shortcut, store: store)

        for _ in 0..<100 where logStore.recentLogs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.shortcuts.first?.lastTriggeredAt != nil)
        #expect(logStore.latestLog(for: shortcut.id)?.output == "trigger")
        #expect(logStore.latestLog(for: shortcut.id)?.succeeded == true)
        #expect(logStore.latestLog(for: shortcut.id)?.duration ?? 0 > 0)
    }

    @MainActor
    private func restore(_ previous: Data?, in defaults: UserDefaults) {
        if let previous {
            defaults.set(previous, forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        } else {
            defaults.removeObject(forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        }
    }
}
