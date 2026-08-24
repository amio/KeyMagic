import AppKit
import SwiftUI

/// Configures ordered, script-backed text slots rendered in the macOS menu bar.
struct MenuBarTextSettingsView: View {
    @Environment(MenuBarTextController.self) private var controller

    @State private var selectedSlotID: UUID?
    @State private var resizePreview: MenuBarSlotResizePreview?

    private var selectedSlot: MenuBarTextSlot? {
        controller.slots.first { $0.id == selectedSlotID }
    }

    private var previewSlots: [MenuBarTextRenderedSlot] {
        controller.previewSlots.map { slot in
            guard let resizePreview, resizePreview.slotID == slot.id else { return slot }
            return MenuBarTextRenderedSlot(
                id: slot.id,
                alignment: slot.alignment,
                widthPoints: resizePreview.widthPoints,
                contents: slot.contents
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            previewBar
                .padding(.horizontal, 24)
                .padding(.top, 20)

            editor
        }
        .navigationTitle("Menu Bar")
        .onAppear {
            reconcileSelection(with: controller.slots.map(\.id))
        }
        .onChange(of: controller.slots.map(\.id)) { _, slotIDs in
            reconcileSelection(with: slotIDs)
        }
    }

    private var previewBar: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    MenuBarStatusPreview(
                        slots: previewSlots,
                        selectedSlotID: selectedSlotID,
                        onSelect: { selectedSlotID = $0 },
                        onResize: previewWidth,
                        onResizeEnd: commitWidth
                    )
                    .id("menu-bar-preview")
                }
                .scrollIndicators(.hidden)
                .onChange(of: controller.slots.count) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo("menu-bar-preview", anchor: .trailing)
                    }
                }
            }

            Divider()
                .padding(.vertical, 7)

            Button {
                selectedSlotID = controller.addSlot()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: MenuBarStatusPreview.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add Slot")
            .accessibilityLabel("Add Slot")
        }
        .padding(.horizontal, 6)
        .frame(height: MenuBarStatusPreview.height)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let slot = selectedSlot,
            let index = controller.slots.firstIndex(where: { $0.id == slot.id })
        {
            MenuBarTextSlotEditor(
                slot: slot,
                index: index,
                slotCount: controller.slots.count,
                onRemove: { removeSelectedSlot(slot, at: index) }
            )
        } else {
            Spacer()
        }
    }

    private func previewWidth(_ slotID: UUID, _ widthPoints: Int) {
        let preview = MenuBarSlotResizePreview(
            slotID: slotID,
            widthPoints: widthPoints
        )
        guard resizePreview != preview else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedSlotID = slotID
            resizePreview = preview
        }
    }

    private func commitWidth(_ slotID: UUID, _ widthPoints: Int) {
        selectedSlotID = slotID
        controller.updateSlot(id: slotID) { $0.widthPoints = widthPoints }
        resizePreview = nil
    }

    private func removeSelectedSlot(_ slot: MenuBarTextSlot, at index: Int) {
        let remainingSlotIDs = controller.slots.filter { $0.id != slot.id }.map(\.id)
        let nextSelection =
            remainingSlotIDs.indices.contains(index)
            ? remainingSlotIDs[index]
            : remainingSlotIDs.last

        controller.removeSlot(id: slot.id)
        selectedSlotID = nextSelection
    }

    private func reconcileSelection(with slotIDs: [UUID]) {
        if let resizePreview, !slotIDs.contains(resizePreview.slotID) {
            self.resizePreview = nil
        }
        if let selectedSlotID, slotIDs.contains(selectedSlotID) {
            return
        }
        selectedSlotID = slotIDs.first
    }
}

private struct MenuBarSlotResizePreview: Equatable {
    let slotID: UUID
    let widthPoints: Int
}
