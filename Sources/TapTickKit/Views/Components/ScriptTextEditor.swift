import AppKit
import Observation
import SwiftUI

/// Owns the native text editor's per-script undo stack and button state.
@MainActor
@Observable
final class ScriptTextUndoController {
    private(set) var canUndo = false
    private(set) var canRedo = false

    let undoManager: UndoManager

    init() {
        undoManager = UndoManager()
    }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refresh()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refresh()
    }

    func reset() {
        undoManager.removeAllActions()
        refresh()
    }

    func refresh() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}

/// A plain-text AppKit editor so buttons and standard keyboard commands share one UndoManager.
struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let undoController: ScriptTextUndoController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }

        let undoManager = undoController.undoManager
        undoManager.disableUndoRegistration()
        textView.string = text
        undoManager.enableUndoRegistration()
        undoController.refresh()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor

        init(parent: ScriptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.undoController.refresh()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoController.undoManager
        }
    }
}
