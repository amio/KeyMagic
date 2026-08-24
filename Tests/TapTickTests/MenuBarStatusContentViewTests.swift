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
        let previewEmptySlot = renderedSlot(
            fitsContentWidth: true,
            contents: [.empty],
            collapsesWhenEmpty: false
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
            MenuBarStatusContentView.width(for: previewEmptySlot)
                == CGFloat(MenuBarTextSlot.widthRange.lowerBound)
        )
        #expect(
            MenuBarStatusContentView.width(for: shortSlot)
                > MenuBarStatusContentView.width(for: previewEmptySlot)
        )
        #expect(
            MenuBarStatusContentView.width(for: longSlot)
                == CGFloat(MenuBarTextSlot.widthRange.upperBound)
        )
    }

    @Test("Runtime slots collapse only when every row is empty")
    @MainActor
    func runtimeSlotsCollapseOnlyWhenEveryRowIsEmpty() {
        let fixedEmptySlot = renderedSlot(
            fitsContentWidth: false,
            contents: [.empty]
        )
        let fittedEmptyRows = renderedSlot(
            fitsContentWidth: true,
            contents: [.empty, .empty]
        )
        let partiallyEmptyRows = renderedSlot(
            fitsContentWidth: true,
            contents: [
                .empty,
                MenuBarTextContent(text: "CPU 9%", isPlaceholder: false),
            ]
        )

        #expect(MenuBarStatusContentView.width(for: fixedEmptySlot) == 0)
        #expect(MenuBarStatusContentView.width(for: fittedEmptyRows) == 0)
        #expect(MenuBarStatusContentView.width(for: partiallyEmptyRows) > 0)
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
        contents: [MenuBarTextContent],
        collapsesWhenEmpty: Bool = true
    ) -> MenuBarTextRenderedSlot {
        MenuBarTextRenderedSlot(
            id: UUID(),
            alignment: .center,
            fitsContentWidth: fitsContentWidth,
            widthPoints: widthPoints,
            contents: contents,
            collapsesWhenEmpty: collapsesWhenEmpty
        )
    }
}
