import AppKit
import SwiftUI

/** Edits one selected menu bar text slot without owning selection or preview state. */
struct MenuBarTextSlotEditor: View {
    @Environment(MenuBarTextController.self) private var controller
    @Environment(ShortcutStore.self) private var store

    let slot: MenuBarTextSlot
    let index: Int
    let slotCount: Int
    let pointerX: CGFloat
    let onRemove: () -> Void

    private static let pointerHeight: CGFloat = 9
    private static let contentPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 12
    private static let controlSpacing: CGFloat = 8
    private static let headerFontSize = NSFont.smallSystemFontSize + 2

    private var scriptShortcuts: [Shortcut] {
        store.shortcuts.filter { shortcut in
            switch shortcut.action {
            case .runScript, .runScriptFile:
                true
            case .launchApp:
                false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.contentPadding)
                .padding(.top, Self.pointerHeight + Self.verticalPadding)
                .padding(.bottom, Self.verticalPadding)
                .background(Color.primary.opacity(0.045))

            Divider()

            lineConfiguration

            Divider()

            scriptBehaviorNote
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(MenuBarEditorCalloutShape(pointerX: pointerX))
        .overlay {
            MenuBarEditorCalloutShape(pointerX: pointerX)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Self.contentPadding) {
            Picker("Layout", selection: slotBinding(\.layout)) {
                ForEach(MenuBarTextLayout.allCases, id: \.self) { layout in
                    MenuBarTextLayoutIcon(layout: layout)
                        .frame(width: 24)
                        .accessibilityLabel(layout.title)
                        .tag(layout)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .help("Choose a one-line or two-line layout")

            Picker("Alignment", selection: slotBinding(\.alignment)) {
                ForEach(MenuBarTextAlignment.allCases, id: \.self) { alignment in
                    Image(systemName: alignment.systemImage)
                        .accessibilityLabel(alignment.title)
                        .tag(alignment)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .help("Choose the text alignment within this slot")

            Toggle("Fit to Content", isOn: slotBinding(\.fitsContentWidth))
                .toggleStyle(.checkbox)
                .fixedSize(horizontal: true, vertical: false)
                .help("Automatically adjust this slot's width to fit its current text")

            Spacer(minLength: Self.contentPadding)

            moveButtons

            MenuBarEditorHeaderButton(
                systemImage: "trash",
                accessibilityLabel: "Remove Slot",
                role: .destructive,
                action: onRemove
            )
            .help("Remove Slot")
        }
        .controlSize(.small)
        .font(.system(size: Self.headerFontSize))
    }

    private var moveButtons: some View {
        HStack(spacing: 2) {
            MenuBarEditorHeaderButton(
                systemImage: "arrow.left",
                accessibilityLabel: "Move Left"
            ) {
                controller.moveSlot(id: slot.id, offset: -1)
            }
            .disabled(index == 0)
            .help("Move Left")

            MenuBarEditorHeaderButton(
                systemImage: "arrow.right",
                accessibilityLabel: "Move Right"
            ) {
                controller.moveSlot(id: slot.id, offset: 1)
            }
            .disabled(index == slotCount - 1)
            .help("Move Right")
        }
    }

    private var lineConfiguration: some View {
        VStack(spacing: 0) {
            ForEach(Array(slot.layout.activeLinePositions.enumerated()), id: \.element) {
                index,
                position in
                if index > 0 {
                    Divider()
                }
                lineConfigurationRow(position: position)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scriptBehaviorNote: some View {
        Text(
            "Scripts refresh in the background at the selected interval. Multiline output is condensed to one line, and the slot collapses when every script returns empty output."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Self.contentPadding)
        .padding(.vertical, Self.verticalPadding)
    }

    private func lineConfigurationRow(position: MenuBarTextLinePosition) -> some View {
        HStack(spacing: Self.controlSpacing) {
            scriptPicker(position: position)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(scriptPickerAccessibilityLabel(position: position))

            Image(systemName: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Refresh interval")

            TextField(
                "Seconds",
                value: lineBinding(position: position, \.refreshIntervalSeconds),
                formatter: DigitsOnlyNumberFormatter.shared
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 54)
            .accessibilityLabel("Refresh interval in seconds")

            Text("s")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Self.contentPadding)
        .padding(.vertical, Self.verticalPadding)
    }

    private func scriptPicker(position: MenuBarTextLinePosition) -> some View {
        let line = slot[position]
        return Picker("Script", selection: lineBinding(position: position, \.scriptID)) {
            Text(scriptShortcuts.isEmpty ? "No Scripts" : "Choose Script…")
                .tag(Optional<UUID>.none)

            if let scriptID = line.scriptID,
                !scriptShortcuts.contains(where: { $0.id == scriptID })
            {
                Text("Missing Script").tag(Optional(scriptID))
            }

            ForEach(scriptShortcuts) { shortcut in
                Text(shortcut.name).tag(Optional(shortcut.id))
            }
        }
        .labelsHidden()
    }

    private func slotBinding<Value>(
        _ keyPath: WritableKeyPath<MenuBarTextSlot, Value>
    ) -> Binding<Value> {
        Binding(
            get: { slot[keyPath: keyPath] },
            set: { value in
                controller.updateSlot(id: slot.id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func lineBinding<Value>(
        position: MenuBarTextLinePosition,
        _ keyPath: WritableKeyPath<MenuBarTextLineConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { slot[position][keyPath: keyPath] },
            set: { value in
                controller.updateSlot(id: slot.id) { updatedSlot in
                    var line = updatedSlot[position]
                    line[keyPath: keyPath] = value
                    updatedSlot[position] = line
                }
            }
        )
    }

    private func scriptPickerAccessibilityLabel(
        position: MenuBarTextLinePosition
    ) -> String {
        guard slot.layout == .twoLines else { return "Script" }
        return position == .top ? "Top script" : "Bottom script"
    }
}

private final class DigitsOnlyNumberFormatter: NumberFormatter, @unchecked Sendable {
    static let shared = DigitsOnlyNumberFormatter()

    private override init() {
        super.init()
        numberStyle = .none
        allowsFloats = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        partialString.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

private struct MenuBarEditorHeaderButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var role: ButtonRole?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .opacity(isHovered && isEnabled ? 1 : 0)
        }
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovered = $0 }
    }
}

private struct MenuBarTextLayoutIcon: View {
    let layout: MenuBarTextLayout

    var body: some View {
        Image(nsImage: image)
            .renderingMode(.template)
            .resizable()
            .frame(width: 22, height: 18)
    }

    private var image: NSImage {
        switch layout {
        case .singleLine:
            Self.singleLineImage
        case .twoLines:
            Self.twoLinesImage
        }
    }

    private static let singleLineImage = makeImage(lineWidths: [10])
    private static let twoLinesImage = makeImage(lineWidths: [10, 10])

    private static func makeImage(lineWidths: [CGFloat]) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()
            let slotPath = NSBezierPath(
                roundedRect: NSRect(x: 1.25, y: 1.25, width: 17.5, height: 13.5),
                xRadius: 3.25,
                yRadius: 3.25
            )
            slotPath.lineWidth = 1
            slotPath.stroke()

            NSColor.black.setFill()
            let lineHeight: CGFloat = 2.25
            let lineSpacing: CGFloat = 2.25
            let totalHeight =
                lineHeight * CGFloat(lineWidths.count)
                + lineSpacing * CGFloat(lineWidths.count - 1)
            var originY = (size.height - totalHeight) / 2

            for width in lineWidths {
                let lineRect = NSRect(
                    x: (size.width - width) / 2,
                    y: originY,
                    width: width,
                    height: lineHeight
                )
                NSBezierPath(
                    roundedRect: lineRect,
                    xRadius: lineHeight / 2,
                    yRadius: lineHeight / 2
                ).fill()
                originY += lineHeight + lineSpacing
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct MenuBarEditorCalloutShape: Shape {
    let pointerX: CGFloat

    private let cornerRadius: CGFloat = 10
    private let pointerHeight: CGFloat = 9
    private let pointerHalfWidth: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + pointerHeight
        let pointerCenter = min(
            max(pointerX, cornerRadius + pointerHalfWidth),
            rect.maxX - cornerRadius - pointerHalfWidth
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: bodyTop))
        path.addLine(to: CGPoint(x: pointerCenter - pointerHalfWidth, y: bodyTop))
        path.addLine(to: CGPoint(x: pointerCenter, y: rect.minY))
        path.addLine(to: CGPoint(x: pointerCenter + pointerHalfWidth, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: bodyTop))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyTop + cornerRadius),
            control: CGPoint(x: rect.maxX, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: bodyTop),
            control: CGPoint(x: rect.minX, y: bodyTop)
        )
        path.closeSubpath()
        return path
    }
}
