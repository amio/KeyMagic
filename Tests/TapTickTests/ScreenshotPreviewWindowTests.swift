import AppKit
@testable import TapTickKit
import Testing

@MainActor
@Suite("Screenshot Preview Window", .serialized)
struct ScreenshotPreviewWindowTests {
    @Test("Tiny captures preserve the complete titlebar toolbar")
    func tinyCapturesPreserveToolbar() async throws {
        let window = ScreenshotPreviewWindow(
            image: NSImage(size: NSSize(width: 1, height: 1))
        )
        window.alphaValue = 0
        window.orderFront(nil)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        #expect(
            window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
        #expect(window.frame.width >= window.minSize.width)
        #expect(window.frame.height >= window.minSize.height)

        let leadingAccessory = try #require(
            window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .left }
        )
        let trailingAccessory = try #require(
            window.titlebarAccessoryViewControllers.first { $0.layoutAttribute == .right }
        )
        let leadingFrame = leadingAccessory.view.convert(leadingAccessory.view.bounds, to: nil)
        let trailingFrame = trailingAccessory.view.convert(trailingAccessory.view.bounds, to: nil)

        #expect(leadingFrame.maxX <= trailingFrame.minX)
    }
}
