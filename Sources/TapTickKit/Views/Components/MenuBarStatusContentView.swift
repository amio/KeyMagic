import AppKit
import CoreText

/** Draws the icon and text slots shared by the real menu bar and Settings preview. */
@MainActor
final class MenuBarStatusContentView: NSView {
    static let height = NSStatusBar.system.thickness
    static let iconAreaWidth = height

    private static let iconName = NSImage.Name("MenuBarIcon")
    private static let iconSize = NSSize(width: 18, height: 18)
    private static let horizontalTextPadding: CGFloat = 4
    private static let twoLineSpacingReduction: CGFloat = 1
    private static let singleLineFont = tabularDigitFont(size: 0)
    private static let twoLineFont = tabularDigitFont(size: 9)

    private let icon = MenuBarStatusContentView.menuBarImage()
    private var slots: [MenuBarTextRenderedSlot] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width(for: slots), height: Self.height)
    }

    static func width(for slots: [MenuBarTextRenderedSlot]) -> CGFloat {
        iconAreaWidth + slots.reduce(0) { $0 + width(for: $1) }
    }

    static func width(for slot: MenuBarTextRenderedSlot) -> CGFloat {
        guard slot.fitsContentWidth else { return CGFloat(slot.widthPoints) }

        let font = font(lineCount: slot.contents.count)
        let contentWidth = slot.contents.reduce(CGFloat.zero) { width, content in
            max(width, textWidth(content.text, font: font))
        }
        return min(
            max(
                ceil(contentWidth + horizontalTextPadding * 2),
                CGFloat(MenuBarTextSlot.widthRange.lowerBound)
            ),
            CGFloat(MenuBarTextSlot.widthRange.upperBound)
        )
    }

    func update(slots: [MenuBarTextRenderedSlot]) {
        self.slots = slots
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let foregroundColor = foregroundColor()
        drawIcon(color: foregroundColor)

        var originX = Self.iconAreaWidth
        for slot in slots {
            let slotWidth = Self.width(for: slot)
            let slotRect = NSRect(
                x: originX,
                y: 0,
                width: slotWidth,
                height: bounds.height
            )
            draw(slot: slot, in: slotRect, foregroundColor: foregroundColor)
            originX += slotWidth
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func drawIcon(color: NSColor) {
        guard let icon else { return }
        let iconRect = NSRect(
            x: (Self.iconAreaWidth - Self.iconSize.width) / 2,
            y: (bounds.height - Self.iconSize.height) / 2,
            width: Self.iconSize.width,
            height: Self.iconSize.height
        )

        icon.draw(
            in: iconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        color.setFill()
        iconRect.fill(using: .sourceAtop)
    }

    private func draw(
        slot: MenuBarTextRenderedSlot,
        in rect: NSRect,
        foregroundColor: NSColor
    ) {
        let font = Self.font(lineCount: slot.contents.count)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let lineStep =
            slot.contents.count == 1
            ? lineHeight
            : max(lineHeight - Self.twoLineSpacingReduction, font.pointSize)
        let totalHeight = lineHeight + lineStep * CGFloat(slot.contents.count - 1)
        var originY = rect.midY + totalHeight / 2 - lineHeight
        let textWidth = max(rect.width - Self.horizontalTextPadding * 2, 0)

        for content in slot.contents {
            let textRect = NSRect(
                x: rect.minX + Self.horizontalTextPadding,
                y: originY,
                width: textWidth,
                height: lineHeight
            )
            NSAttributedString(
                string: content.text,
                attributes: textAttributes(
                    font: font,
                    color: content.isPlaceholder ? .secondaryLabelColor : foregroundColor,
                    alignment: slot.alignment
                )
            ).draw(in: textRect)
            originY -= lineStep
        }
    }

    private func textAttributes(
        font: NSFont,
        color: NSColor,
        alignment: MenuBarTextAlignment
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment(for: alignment)
        paragraphStyle.lineBreakMode = .byTruncatingTail

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private func textAlignment(for alignment: MenuBarTextAlignment) -> NSTextAlignment {
        switch alignment {
        case .left:
            .left
        case .center:
            .center
        case .right:
            .right
        }
    }

    private static func font(lineCount: Int) -> NSFont {
        lineCount == 1 ? Self.singleLineFont : Self.twoLineFont
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func tabularDigitFont(size: CGFloat) -> NSFont {
        let baseFont = NSFont.menuBarFont(ofSize: size)
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]
            ]
        ])
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    private func foregroundColor() -> NSColor {
        guard let button = superview as? NSStatusBarButton,
            button.cell?.isHighlighted == true
        else {
            return .labelColor
        }
        return .selectedMenuItemTextColor
    }

    private static func menuBarImage() -> NSImage? {
        if let image = NSImage(named: iconName)?.copy() as? NSImage {
            image.isTemplate = true
            return image
        }

        guard
            let image = NSImage(
                systemSymbolName: "keyboard.badge.ellipsis",
                accessibilityDescription: nil
            )
        else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        configuredImage.size = iconSize
        configuredImage.isTemplate = true
        return configuredImage
    }
}
