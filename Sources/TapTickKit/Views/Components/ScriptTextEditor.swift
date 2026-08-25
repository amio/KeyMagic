import AppKit
import Observation
import SwiftUI

/// Owns the native text editor's per-script commands, undo stack, and button state.
@MainActor
@Observable
final class ScriptTextEditorController {
    private(set) var canUndo = false
    private(set) var canRedo = false

    let undoManager: UndoManager

    @ObservationIgnored
    private weak var textView: NSTextView?

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

    /// Applies an editor-originated whole-document change as one native undoable edit.
    @discardableResult
    func replaceAll(with replacement: String, actionName: String) -> Bool {
        guard let textView else { return false }
        guard textView.string != replacement else { return true }

        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.insertText(replacement, replacementRange: fullRange)
        undoManager.setActionName(actionName)
        refresh()
        return true
    }

    func reset() {
        undoManager.removeAllActions()
        refresh()
    }

    func refresh() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    func attach(to textView: NSTextView) {
        guard self.textView !== textView else { return }
        self.textView = textView
        reset()
    }

    func detach(from textView: NSTextView) {
        guard self.textView === textView else { return }
        self.textView = nil
    }
}

/// A plain-text AppKit editor so buttons and standard keyboard commands share one UndoManager.
struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: ScriptTextEditorController

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
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.writingToolsBehavior = .none
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        context.coordinator.attach(to: textView, controller: controller)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.attach(to: textView, controller: controller)
        guard textView.string != text else { return }

        let undoManager = controller.undoManager
        undoManager.disableUndoRegistration()
        textView.string = text
        undoManager.enableUndoRegistration()
        controller.refresh()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.detach(from: textView, controller: coordinator.parent.controller)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor

        private weak var observedTextView: NSTextView?
        private var observedUndoManager: UndoManager?

        init(parent: ScriptTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to textView: NSTextView, controller: ScriptTextEditorController) {
            controller.attach(to: textView)
            guard observedTextView !== textView || observedUndoManager !== controller.undoManager else {
                return
            }

            stopObservingUndoChanges()
            observedTextView = textView
            observedUndoManager = controller.undoManager
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(undoManagerDidChange),
                name: Notification.Name.NSUndoManagerDidUndoChange,
                object: controller.undoManager
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(undoManagerDidChange),
                name: Notification.Name.NSUndoManagerDidRedoChange,
                object: controller.undoManager
            )
        }

        func detach(from textView: NSTextView, controller: ScriptTextEditorController) {
            guard observedTextView === textView else { return }
            stopObservingUndoChanges()
            controller.detach(from: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            synchronizeText(from: textView)
        }

        @objc private func undoManagerDidChange(_ notification: Notification) {
            guard let textView = observedTextView else { return }
            synchronizeText(from: textView)
        }

        private func synchronizeText(from textView: NSTextView) {
            parent.text = textView.string
            parent.controller.refresh()
        }

        private func stopObservingUndoChanges() {
            guard let observedUndoManager else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: Notification.Name.NSUndoManagerDidUndoChange,
                object: observedUndoManager
            )
            NotificationCenter.default.removeObserver(
                self,
                name: Notification.Name.NSUndoManagerDidRedoChange,
                object: observedUndoManager
            )
            self.observedUndoManager = nil
            observedTextView = nil
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.controller.undoManager
        }
    }
}
