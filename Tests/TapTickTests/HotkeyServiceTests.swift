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

    @Test("Built-in feature hotkeys participate in conflict detection")
    @MainActor
    func builtInFeatureConflicts() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickHotkeyService-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ShortcutStore(directory: directory)
        let builtInFeatures = BuiltInFeatureController(directory: directory)
        let service = HotkeyService()

        service.start(store: store, builtInFeatures: builtInFeatures)
        defer { service.stop() }

        let reservedHotkey = builtInFeatures.keystrokeOverlay.hotkey
        #expect(service.hasConflict(keyCombo: reservedHotkey))
        #expect(
            service.hasConflict(
                keyCombo: reservedHotkey,
                excludingBuiltInFeatureID: .keystrokeOverlay
            ) == false
        )
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
