import Cocoa
import SwiftUI

/// A reusable hotkey table-cell that supports recording, displaying, editing, and deleting a key combo.
///
/// Three visual states:
/// 1. **Empty** – shows a "Record Hotkey" button.
/// 2. **Recording** – pulsing red indicator with "Press keys…"; Escape cancels.
/// 3. **Bound** – displays the key combo badge plus edit / delete icon buttons.
///
/// The parent owns the "which item is recording" state and drives `isRecording` from outside,
/// so that only one cell can record at a time across the entire list.
struct HotkeyCellView: View {
    /// The current key combo (nil = no hotkey bound).
    let keyCombo: KeyCombo?
    /// Whether this cell is currently in recording mode.
    let isRecording: Bool
    /// Called when the user wants to start (or re-start) recording.
    let onStartRecording: () -> Void
    /// Called with the captured key combo after a successful recording.
    let onRecordKey: (KeyCombo) -> Void
    /// Called when the user cancels recording (Escape or disappear).
    let onCancelRecording: () -> Void
    /// Called when the user clicks the delete button.
    let onClearHotkey: () -> Void

    @State private var monitor: Any?

    var body: some View {
        Group {
            if isRecording {
                recordingContent
            } else if let keyCombo {
                boundContent(keyCombo)
            } else {
                emptyContent
            }
        }
        .onDisappear {
            if isRecording {
                stopLocalMonitor()
                onCancelRecording()
            }
        }
    }

    // MARK: - Recording State

    private var recordingContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text("Press keys...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.red.opacity(0.5), lineWidth: 1)
        )
        .onAppear { startLocalMonitor() }
        .onDisappear { stopLocalMonitor() }
    }

    // MARK: - Bound State (combo + edit + delete)

    private func boundContent(_ combo: KeyCombo) -> some View {
        HStack(spacing: 4) {
            Text(combo.displayString)
                .font(.system(.callout))
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)
                )

            Button {
                onStartRecording()
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit hotkey")

            Button {
                onClearHotkey()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove hotkey")
        }
    }

    // MARK: - Empty State

    private var emptyContent: some View {
        Button("Record Hotkey") {
            onStartRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Key Recording (local monitor)

    private func startLocalMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Consume modifier-only events without recording
            if event.type == .flagsChanged {
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            let modifiers = KeyCombo.Modifiers(
                cgEventFlags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))

            // Escape without modifiers cancels recording
            if keyCode == UInt32(0x35) && modifiers == [] {
                stopLocalMonitor()
                onCancelRecording()
                return nil
            }

            let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
            stopLocalMonitor()
            onRecordKey(combo)
            return nil
        }
    }

    private func stopLocalMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
