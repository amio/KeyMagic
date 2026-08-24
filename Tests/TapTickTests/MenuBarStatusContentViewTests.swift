import Foundation
import Testing
@testable import TapTickKit

@Suite("Menu Bar Status Content")
struct MenuBarStatusContentViewTests {
    @Test("Fixed width ignores content length")
    @MainActor
    func fixedWidthIgnoresContentLength() {
        let slot = renderedSlot(
            fitsContentWidth: false,
            widthPoints: 88,
            contents: [MenuBarTextContent(text: String(repeating: "W", count: 100), isPlaceholder: false)]
        )

        #expect(MenuBarStatusContentView.width(for: slot) == 88)
    }

    @Test("Content-fitted width follows text within slot bounds")
    @MainActor
    func contentFittedWidthFollowsTextWithinBounds() {
        let emptySlot = renderedSlot(
            fitsContentWidth: true,
            contents: [.empty]
        )
        let shortSlot = renderedSlot(
            fitsContentWidth: true,
            contents: [MenuBarTextContent(text: "CPU 9%", isPlaceholder: false)]
        )
        let longSlot = renderedSlot(
            fitsContentWidth: true,
            contents: [MenuBarTextContent(text: String(repeating: "W", count: 100), isPlaceholder: false)]
        )

        #expect(
            MenuBarStatusContentView.width(for: emptySlot)
                == CGFloat(MenuBarTextSlot.widthRange.lowerBound)
        )
        #expect(
            MenuBarStatusContentView.width(for: shortSlot)
                > MenuBarStatusContentView.width(for: emptySlot)
        )
        #expect(
            MenuBarStatusContentView.width(for: longSlot)
                == CGFloat(MenuBarTextSlot.widthRange.upperBound)
        )
    }

    @Test("Two-line content-fitted width follows the wider row")
    @MainActor
    func twoLineContentFittedWidthFollowsWiderRow() {
        let shortRows = renderedSlot(
            fitsContentWidth: true,
            contents: [
                MenuBarTextContent(text: "A", isPlaceholder: false),
                MenuBarTextContent(text: "B", isPlaceholder: false),
            ]
        )
        let oneLongRow = renderedSlot(
            fitsContentWidth: true,
            contents: [
                MenuBarTextContent(text: "A", isPlaceholder: false),
                MenuBarTextContent(text: "Longer bottom row", isPlaceholder: false),
            ]
        )

        #expect(
            MenuBarStatusContentView.width(for: oneLongRow)
                > MenuBarStatusContentView.width(for: shortRows)
        )
    }

    @MainActor
    private func renderedSlot(
        fitsContentWidth: Bool,
        widthPoints: Int = MenuBarTextSlot.defaultWidthPoints,
        contents: [MenuBarTextContent]
    ) -> MenuBarTextRenderedSlot {
        MenuBarTextRenderedSlot(
            id: UUID(),
            alignment: .center,
            fitsContentWidth: fitsContentWidth,
            widthPoints: widthPoints,
            contents: contents
        )
    }
}
