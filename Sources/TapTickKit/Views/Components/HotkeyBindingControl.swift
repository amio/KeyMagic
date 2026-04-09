import Carbon.HIToolbox
import Cocoa
import SwiftUI

/// A compact hotkey binding control shared by list cells and settings forms.
///
/// The parent owns the persisted value and decides whether recording is active,
/// which keeps the interaction reusable in both single-item forms and multi-row lists.
struct HotkeyBindingControl: View {
    @Environment(HotkeyService.self) private var hotkeyService

    let keyCombo: KeyCombo?
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecordKey: (KeyCombo) -> Void
    let onCancelRecording: () -> Void
    var onClearHotkey: (() -> Void)? = nil
    var checkConflict: ((KeyCombo) -> Bool)?
    var emptyTitle = "Record Hotkey"

    @State private var monitor: Any?
    /// Live preview text shown while recording. nil = nothing pressed yet.
    @State private var previewText: String?
    @State private var conflictingCombo: KeyCombo?

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
        .alert(
            "Shortcut Conflict",
            isPresented: Binding(get: { conflictingCombo != nil }, set: { if !$0 { conflictingCombo = nil } })
        ) {
            Button("OK") { conflictingCombo = nil }
        } message: {
            if let combo = conflictingCombo {
                Text("\(combo.displayString) is already bound to another shortcut.")
            }
        }
    }

    // MARK: - Recording State

    private var recordingContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            if let previewText {
                Text(previewText)
                    .font(.body)
                    .fontWeight(.medium)
                    .tracking(1)
            } else {
                Text("Press keys...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(width: 97, height: 20, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.red.opacity(0.5), lineWidth: 1)
        )
        .onAppear { startLocalMonitor() }
        .onDisappear { stopLocalMonitor() }
    }

    // MARK: - Bound State

    private func boundContent(_ combo: KeyCombo) -> some View {
        HStack(spacing: 4) {
            Button {
                onStartRecording()
            } label: {
                Text(combo.displayString)
                    .tracking(1.5)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Click to re-bind hotkey")

            if let onClearHotkey {
                Button {
                    onClearHotkey()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove hotkey")
            }
        }
    }

    // MARK: - Empty State

    private var emptyContent: some View {
        Button(emptyTitle) {
            onStartRecording()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Key Recording

    private func startLocalMonitor() {
        previewText = nil
        hotkeyService.suspendRegistrations()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handleEvent(event)
            return nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = KeyCombo.Modifiers(nsEventFlags: event.modifierFlags)

        if event.type == .flagsChanged {
            previewText = modifiers.isEmpty ? nil : modifiers.displayString
            return
        }

        if event.type == .keyUp {
            let primaryModifiers: KeyCombo.Modifiers = [.command, .control, .option]
            if modifiers.intersection(primaryModifiers).isEmpty {
                previewText = modifiers.isEmpty ? nil : modifiers.displayString
            }
            return
        }

        if keyCode == UInt32(kVK_Escape) && modifiers == [] {
            stopLocalMonitor()
            onCancelRecording()
            return
        }

        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        previewText = combo.displayString

        let primaryModifiers: KeyCombo.Modifiers = [.command, .control, .option]
        guard !modifiers.intersection(primaryModifiers).isEmpty else { return }

        if checkConflict?(combo) == true {
            conflictingCombo = combo
            stopLocalMonitor()
            onCancelRecording()
            return
        }

        stopLocalMonitor()
        onRecordKey(combo)
    }

    private func stopLocalMonitor() {
        let hadMonitor = monitor != nil
        previewText = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if hadMonitor {
            hotkeyService.resumeRegistrations()
        }
    }
}
