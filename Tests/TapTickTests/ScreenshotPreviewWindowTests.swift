import AppKit
import Carbon.HIToolbox
@testable import TapTickKit
import Testing

@MainActor
@Suite("Screenshot Preview Window", .serialized)
struct ScreenshotPreviewWindowTests {
    @Test("Tab cycles colors forward and Shift-Tab cycles backward")
    func tabCyclesAnnotationColorsInBothDirections() throws {
        let window = ScreenshotPreviewWindow(
            image: NSImage(size: NSSize(width: 640, height: 480))
        )
        defer { window.close() }

        var selectedColorIndices: [Int] = []
        window.onAnnotationSettingsChanged = { _, colorIndex in
            selectedColorIndices.append(colorIndex)
        }

        window.keyDown(with: try keyEvent(keyCode: kVK_Tab))
        window.keyDown(with: try keyEvent(keyCode: kVK_Tab, modifiers: .shift))
        window.keyDown(with: try keyEvent(keyCode: kVK_Tab, modifiers: .shift))

        #expect(selectedColorIndices == [1, 0, AnnotationPalette.colors.count - 1])
    }

    @Test("Canvas meets the titlebar and keeps equal margins on the remaining edges")
    func canvasLayoutMatchesToolbarChrome() async throws {
        let window = ScreenshotPreviewWindow(
            image: NSImage(size: NSSize(width: 640, height: 480))
        )
        window.alphaValue = 0
        window.show()
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        let rootView = try #require(window.contentView)
        let shadowContainer = try #require(rootView.subviews.first { $0.shadow != nil })
        let rootFrame = rootView.convert(rootView.bounds, to: nil)
        let canvasFrame = shadowContainer.convert(shadowContainer.bounds, to: nil)
        let expectedMargin: CGFloat = 10

        #expect(abs(canvasFrame.maxY - window.contentLayoutRect.maxY) < 0.5)
        #expect(abs(canvasFrame.minX - rootFrame.minX - expectedMargin) < 0.5)
        #expect(abs(rootFrame.maxX - canvasFrame.maxX - expectedMargin) < 0.5)
        #expect(abs(canvasFrame.minY - rootFrame.minY - expectedMargin) < 0.5)
    }

    @Test("Tiny captures inherit appearance and preserve the complete titlebar toolbar")
    func tinyCapturesPreserveToolbar() async throws {
        let window = ScreenshotPreviewWindow(
            image: NSImage(size: NSSize(width: 1, height: 1))
        )
        window.alphaValue = 0
        window.show()
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        #expect(window.appearance == nil)
        #expect(window.frame.width >= window.minSize.width)
        #expect(window.frame.height >= window.minSize.height)

        let closeButton = try #require(window.standardWindowButton(.closeButton))
        let miniaturizeButton = try #require(window.standardWindowButton(.miniaturizeButton))
        let zoomButton = try #require(window.standardWindowButton(.zoomButton))
        #expect(!closeButton.isHidden)
        #expect(miniaturizeButton.isHidden)
        #expect(zoomButton.isHidden)

        let leadingAccessory = try #require(
            window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .left }
        )
        let trailingAccessory = try #require(
            window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .right }
        )
        let leadingFrame = leadingAccessory.view.convert(leadingAccessory.view.bounds, to: nil)
        let trailingFrame = trailingAccessory.view.convert(trailingAccessory.view.bounds, to: nil)
        let closeFrame = closeButton.convert(closeButton.bounds, to: nil)

        #expect(leadingFrame.maxX <= trailingFrame.minX)
        #expect(leadingFrame.minX - closeFrame.maxX <= 16)
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\t",
                charactersIgnoringModifiers: "\t",
                isARepeat: false,
                keyCode: UInt16(keyCode)
            ))
    }
}
