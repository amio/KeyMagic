import AppKit
import SwiftUI
import Testing
@testable import TapTickKit

@Suite("ScriptTextEditor")
@MainActor
struct ScriptTextEditorTests {
    @Test("Loading a script establishes a clean saved baseline")
    func loadingDraftIsSaved() {
        let shortcut = Shortcut(
            name: "Example",
            action: .runScript(script: "echo initial", shell: .zsh)
        )
        var state = ScriptEditorDraftState()

        state.load(shortcut)
        let savedDraft = state.draft
        #expect(!state.hasUnsavedChanges)

        state.draft.scriptContent = "echo changed"
        #expect(state.hasUnsavedChanges)

        state.draft = savedDraft
        #expect(!state.hasUnsavedChanges)

        state.draft.name = "Renamed"
        state.markSaved()
        #expect(!state.hasUnsavedChanges)
    }

    @Test("Native undo and redo share the editor controller")
    func nativeUndoRedo() {
        let text = TextBox("a")
        let controller = ScriptTextEditorController()
        let editor = ScriptTextEditor(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            shell: .zsh,
            controller: controller
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        textView.delegate = coordinator
        textView.allowsUndo = true
        textView.string = text.value
        coordinator.attach(to: textView, controller: controller)
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        #expect(text.value == "ab")
        #expect(controller.undoManager.levelsOfUndo == 0)
        #expect(controller.undoManager.canUndo)

        controller.undo()
        #expect(text.value == "a")
        #expect(controller.canRedo)

        controller.redo()
        #expect(text.value == "ab")
    }

    @Test("Editor command replacement is a single native undoable change")
    func editorCommandReplacement() {
        let text = TextBox("old")
        let controller = ScriptTextEditorController()
        let editor = ScriptTextEditor(
            text: Binding(
                get: { text.value },
                set: { text.value = $0 }
            ),
            shell: .zsh,
            controller: controller
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView()
        textView.delegate = coordinator
        textView.allowsUndo = true
        textView.string = text.value
        coordinator.attach(to: textView, controller: controller)

        #expect(controller.replaceAll(with: "generated", actionName: "Generate Script"))
        #expect(textView.string == "generated")
        #expect(text.value == "generated")
        #expect(controller.undoManager.undoActionName == "Generate Script")

        controller.undo()
        #expect(textView.string == "old")
        #expect(text.value == "old")
        #expect(controller.canRedo)
    }
}

@MainActor
private final class TextBox {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}
