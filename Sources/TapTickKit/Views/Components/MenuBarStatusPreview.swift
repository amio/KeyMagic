import AppKit
import SwiftUI

/** Adds Settings-only selection and resize interaction around the production status renderer. */
struct MenuBarStatusPreview: View {
    static var height: CGFloat {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleMenuBarHeight = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
        return max(MenuBarStatusContentView.height, visibleMenuBarHeight)
    }

    let slots: [MenuBarTextRenderedSlot]
    let selectedSlotID: UUID?
    let onSelect: (UUID) -> Void
    let onResize: (UUID, Int) -> Void
    let onResizeEnd: (UUID, Int) -> Void

    private static let highlightVerticalInset: CGFloat = 3
    private static let highlightCornerRadius: CGFloat = 5

    private var width: CGFloat {
        MenuBarStatusContentView.width(for: slots)
    }

    private var height: CGFloat {
        Self.height
    }

    var body: some View {
        ZStack(alignment: .leading) {
            selectionBackgrounds

            MenuBarStatusContentRepresentable(slots: slots)
                .frame(width: width, height: MenuBarStatusContentView.height)

            HStack(spacing: 0) {
                Color.clear
                    .frame(
                        width: MenuBarStatusContentView.iconAreaWidth,
                        height: height
                    )
                    .allowsHitTesting(false)

                ForEach(slots) { slot in
                    MenuBarSlotInteraction(
                        widthPoints: slot.widthPoints,
                        isSelected: selectedSlotID == slot.id,
                        height: height,
                        onSelect: { onSelect(slot.id) },
                        onResize: { onResize(slot.id, $0) },
                        onResizeEnd: { onResizeEnd(slot.id, $0) }
                    )
                }
            }
        }
        .frame(width: width, height: height)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var selectionBackgrounds: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(
                    width: MenuBarStatusContentView.iconAreaWidth,
                    height: height
                )

            ForEach(slots) { slot in
                Color.clear
                    .frame(width: CGFloat(slot.widthPoints), height: height)
                    .overlay {
                        if selectedSlotID == slot.id {
                            RoundedRectangle(
                                cornerRadius: Self.highlightCornerRadius,
                                style: .continuous
                            )
                            .fill(Color.accentColor.opacity(0.12))
                            .padding(.horizontal, 3)
                            .padding(.vertical, Self.highlightVerticalInset)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MenuBarSlotInteraction: View {
    let widthPoints: Int
    let isSelected: Bool
    let height: CGFloat
    let onSelect: () -> Void
    let onResize: (Int) -> Void
    let onResizeEnd: (Int) -> Void

    @State private var isResizeHovered = false
    @State private var dragStartWidthPoints: Int?

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                Color.clear
                    .frame(width: CGFloat(widthPoints), height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Configure menu bar slot")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            resizeHandle
        }
        .frame(width: CGFloat(widthPoints), height: height)
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 10, height: height)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.secondary.opacity(0.72))
                    .frame(width: 2, height: 14)
                    .offset(x: 5)
                    .opacity(isResizeHovered || dragStartWidthPoints != nil ? 1 : 0)
            }
            .highPriorityGesture(resizeGesture)
            .simultaneousGesture(
                TapGesture().onEnded {
                    onSelect()
                }
            )
            .onHover { isHovering in
                isResizeHovered = isHovering
                if isHovering {
                    NSCursor.resizeLeftRight.set()
                } else if dragStartWidthPoints == nil {
                    NSCursor.arrow.set()
                }
            }
            .accessibilityLabel("Resize menu bar slot")
            .accessibilityValue("\(widthPoints) points")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 4 : -4
                onResizeEnd(clampedWidth(widthPoints + delta))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let startWidth = dragStartWidthPoints ?? widthPoints
                if dragStartWidthPoints == nil {
                    dragStartWidthPoints = startWidth
                    onSelect()
                }
                onResize(clampedWidth(startWidth + Int(value.translation.width.rounded())))
            }
            .onEnded { value in
                let startWidth = dragStartWidthPoints ?? widthPoints
                let width = clampedWidth(startWidth + Int(value.translation.width.rounded()))
                onResizeEnd(width)
                dragStartWidthPoints = nil
                if !isResizeHovered {
                    NSCursor.arrow.set()
                }
            }
    }

    private func clampedWidth(_ widthPoints: Int) -> Int {
        min(
            max(widthPoints, MenuBarTextSlot.widthRange.lowerBound),
            MenuBarTextSlot.widthRange.upperBound
        )
    }
}

private struct MenuBarStatusContentRepresentable: NSViewRepresentable {
    let slots: [MenuBarTextRenderedSlot]

    func makeNSView(context: Context) -> MenuBarStatusContentView {
        MenuBarStatusContentView(frame: .zero)
    }

    func updateNSView(_ nsView: MenuBarStatusContentView, context: Context) {
        nsView.update(slots: slots)
    }
}
