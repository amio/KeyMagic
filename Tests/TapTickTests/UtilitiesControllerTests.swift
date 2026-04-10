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

    @Test("Preview sessions suppress event presentations until they expire")
    func previewSessionsSuppressEventPresentations() {
        var coordinator = KeystrokeOverlayPresentationCoordinator()
        coordinator.begin(.preview)

        #expect(coordinator.isPreviewActive)
        #expect(coordinator.allowsEventPresentation == false)
        #expect(coordinator.stopCapture() == .keepPresentation)
        #expect(coordinator.isPreviewActive)
    }

    @Test("Stopping capture only dismisses event presentations")
    func stoppingCaptureDismissesOnlyEventPresentations() {
        var coordinator = KeystrokeOverlayPresentationCoordinator()
        coordinator.begin(.event)

        #expect(coordinator.allowsEventPresentation)
        #expect(coordinator.stopCapture() == .hidePresentation)
        #expect(coordinator.activeIntent == nil)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TapTickUtilities-\(UUID().uuidString)")
    }
}
