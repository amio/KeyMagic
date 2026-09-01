import Testing
import Foundation
@testable import TapTickKit

@Suite("Shortcut")
struct ShortcutTests {
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 0, modifiers: [.command, .shift])
        let action = ShortcutAction.launchApp(bundleIdentifier: "com.apple.finder", appName: "Finder")
        let shortcut = Shortcut(name: "Open Finder", keyCombo: combo, action: action)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(shortcut)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)

        #expect(decoded.id == shortcut.id)
        #expect(decoded.name == shortcut.name)
        #expect(decoded.keyCombo == shortcut.keyCombo)
        #expect(decoded.action == shortcut.action)
        #expect(decoded.isEnabled == shortcut.isEnabled)
    }
}
