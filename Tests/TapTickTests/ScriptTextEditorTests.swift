import AppKit
import SwiftUI
import Testing
@testable import TapTickKit

@Suite("ScriptTextEditor")
@MainActor
struct ScriptTextEditorTests {
    @Test("Editor keeps long lines unwrapped and provides horizontal scrolling")
    func nonWrappingLayout() throws {
        let scrollView = NSTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? NSTextView)
        let textContainer = try #require(textView.textContainer)
        let layoutManager = try #require(textView.layoutManager)
        scrollView.frame = NSRect(x: 0, y: 0, width: 240, height: 120)
        textView.string = String(repeating: "a", count: 200)

        ScriptTextEditor.configureNonWrappingLayout(textView, in: scrollView)
        ScriptTextEditor.resizeDocumentView(textView, in: scrollView)
        layoutManager.ensureLayout(for: textContainer)
        scrollView.layoutSubtreeIfNeeded()

        #expect(scrollView.hasHorizontalScroller)
        #expect(textView.textContainer?.widthTracksTextView == false)
        #expect(layoutManager.usedRect(for: textContainer).width > scrollView.contentSize.width)
        #expect(textView.frame.width > scrollView.documentVisibleRect.width)
    }

    @Test("Loading a script establishes a clean saved baseline")
    func loadingDraftIsSaved() {
        let shortcut = Shortcut(
            name: "Example",
            action: .runScript(script: "#!/bin/zsh\necho initial")
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

    @Test("Switching scripts retargets the draft without carrying editor state")
    func switchingDraftRetargetsEditorState() throws {
        let first = Shortcut(
            name: "First",
            action: .runScript(script: "#!/bin/zsh\necho first")
        )
        let second = Shortcut(
            name: "Second",
            action: .runScript(script: "#!/bin/bash\necho second")
        )
        var state = ScriptEditorDraftState(shortcut: first)

        state.draft.name = "Edited First"
        let firstUpdate = try #require(state.shortcutWithCurrentDraft())
        #expect(firstUpdate.id == first.id)
        #expect(firstUpdate.name == "Edited First")

        state.load(second)

        #expect(state.loadedShortcutID == second.id)
        #expect(state.draft.name == "Second")
        #expect(state.draft.scriptContent == "#!/bin/bash\necho second")
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
            language: .shell(.zsh),
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

    @Test("Unrelated store updates preserve a dirty editor draft")
    func unrelatedStoreUpdatePreservesDraft() throws {
        let shortcut = Shortcut(
            name: "Example",
            action: .runScript(script: "#!/bin/zsh\necho saved")
        )
        var state = ScriptEditorDraftState(shortcut: shortcut)
        state.draft.scriptContent = "#!/bin/zsh\necho draft"
        var triggered = shortcut
        triggered.keyCombo = KeyCombo(keyCode: 12, modifiers: .command)
        triggered.lastTriggeredAt = Date()

        #expect(!state.hasPersistedEditorChange(in: triggered))
        state.updateLoadedMetadata(triggered)

        let update = try #require(state.shortcutWithCurrentDraft())
        #expect(update.keyCombo == triggered.keyCombo)
        #expect(update.action == .runScript(script: "#!/bin/zsh\necho draft"))

        var externallyEdited = triggered
        externallyEdited.action = .runScript(script: "#!/bin/sh\necho external")
        #expect(state.hasPersistedEditorChange(in: externallyEdited))
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
            language: .shell(.zsh),
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
