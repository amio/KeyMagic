import AppKit
import SwiftUI
import Testing
@testable import TapTickKit

@Suite("ScriptTextEditor")
@MainActor
struct ScriptTextEditorTests {
    @Test("Native undo and redo share the editor controller")
    func nativeUndoRedo() {
        let text = TextBox("a")
        let controller = ScriptTextUndoController()
        let editor = ScriptTextEditor(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            undoController: controller
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        textView.delegate = coordinator
        textView.allowsUndo = true
        textView.string = text.value
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(text.value == "ab")
        #expect(controller.undoManager.levelsOfUndo == 0)
        #expect(controller.undoManager.canUndo)

        controller.undo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(text.value == "a")
        #expect(controller.canRedo)

        controller.redo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(text.value == "ab")
    }
}

@MainActor
private final class TextBox {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}
