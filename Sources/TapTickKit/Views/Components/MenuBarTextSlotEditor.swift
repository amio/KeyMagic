import AppKit
import SwiftUI

/** Edits one selected menu bar text slot without owning selection or preview state. */
struct MenuBarTextSlotEditor: View {
    @Environment(MenuBarTextController.self) private var controller
    @Environment(ShortcutStore.self) private var store

    let slot: MenuBarTextSlot
    let index: Int
    let slotCount: Int
    let onRemove: () -> Void

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
        VStack(alignment: .leading, spacing: 16) {
            toolbar
            lineConfiguration
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("Layout", selection: slotBinding(\.layout)) {
                ForEach(MenuBarTextLayout.allCases, id: \.self) { layout in
                    Text(layout.title).tag(layout)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

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

            Spacer()

            Button {
                controller.moveSlot(id: slot.id, offset: -1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(index == 0)
            .help("Move Left")

            Button {
                controller.moveSlot(id: slot.id, offset: 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(index == slotCount - 1)
            .help("Move Right")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .help("Remove Slot")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
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
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func lineConfigurationRow(position: MenuBarTextLinePosition) -> some View {
        HStack(spacing: 10) {
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
                format: .number
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 54)
            .accessibilityLabel("Refresh interval in seconds")

            Text("s")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
