import Carbon.HIToolbox
import Foundation
import Testing
@testable import TapTickKit

@Suite("UtilitiesController")
struct UtilitiesControllerTests {
    @Test("Persists keystroke overlay configuration")
    @MainActor
    func persistsKeystrokeOverlayConfiguration() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let overrideHotkey = KeyCombo(
            keyCode: UInt32(kVK_ANSI_Slash),
            modifiers: [.command, .option]
        )

        let controller = UtilitiesController(directory: directory)
        controller.keystrokeOverlay.fontSize = 48
        controller.keystrokeOverlay.holdDuration = 2.4
        controller.updateKeystrokeOverlayHotkey(overrideHotkey)

        let reloaded = UtilitiesController(directory: directory)
        #expect(reloaded.keystrokeOverlay.fontSize == 48)
        #expect(reloaded.keystrokeOverlay.holdDuration == 2.4)
        #expect(reloaded.keystrokeOverlay.hotkey == overrideHotkey)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickUtilities-\(UUID().uuidString)")
    }
}