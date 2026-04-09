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

    @MainActor
    private func restore(_ previous: Data?, in defaults: UserDefaults) {
        if let previous {
            defaults.set(previous, forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        } else {
            defaults.removeObject(forKey: HotkeyService.settingsWindowHotkeyDefaultsKey)
        }
    }
}
