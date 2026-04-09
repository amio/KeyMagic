import SwiftUI

/// Table-oriented wrapper around the shared compact hotkey binding control.
struct HotkeyCellView: View {
    let keyCombo: KeyCombo?
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecordKey: (KeyCombo) -> Void
    let onCancelRecording: () -> Void
    let onClearHotkey: () -> Void
    var checkConflict: ((KeyCombo) -> Bool)?

    var body: some View {
        HotkeyBindingControl(
            keyCombo: keyCombo,
            isRecording: isRecording,
            onStartRecording: onStartRecording,
            onRecordKey: onRecordKey,
            onCancelRecording: onCancelRecording,
            onClearHotkey: onClearHotkey,
            checkConflict: checkConflict
        )
    }
}
