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
        if let textView {
            let documentStart = NSRange(location: 0, length: 0)
            textView.setSelectedRange(documentStart)
            textView.scrollRangeToVisible(documentStart)
        }
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
    let language: ScriptLanguage?
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
        Self.configureNonWrappingLayout(textView, in: scrollView)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        context.coordinator.attach(to: textView, in: scrollView, controller: controller)
        context.coordinator.highlightIfNeeded(textView)

        return scrollView
    }

    static func configureNonWrappingLayout(_ textView: NSTextView, in scrollView: NSScrollView) {
        scrollView.hasHorizontalScroller = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.size = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
    }

    static func resizeDocumentView(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let contentWidth =
            layoutManager.usedRect(for: textContainer).maxX
            + (textView.textContainerInset.width * 2)
        let documentWidth = max(scrollView.contentSize.width, ceil(contentWidth))
        guard textView.frame.width != documentWidth else { return }
        textView.setFrameSize(NSSize(width: documentWidth, height: textView.frame.height))
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.attach(to: textView, in: scrollView, controller: controller)
        if textView.string != text {
            let undoManager = controller.undoManager
            undoManager.disableUndoRegistration()
            textView.string = text
            undoManager.enableUndoRegistration()
            controller.refresh()
        }
        context.coordinator.highlightIfNeeded(textView)
        context.coordinator.resizeDocumentView(textView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.detach(from: textView, controller: coordinator.parent.controller)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor

        private weak var observedTextView: NSTextView?
        private weak var observedScrollView: NSScrollView?
        private var observedUndoManager: UndoManager?
        private var highlightedText: String?
        private var highlightedLanguage: ScriptLanguage?
        private var wasHighlighted = false
        private var highlightRequestID = 0
        private var highlightTask: Task<Void, Never>?

        init(parent: ScriptTextEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(
            to textView: NSTextView,
            in scrollView: NSScrollView? = nil,
            controller: ScriptTextEditorController
        ) {
            controller.attach(to: textView)
            guard
                observedTextView !== textView || observedScrollView !== scrollView
                    || observedUndoManager !== controller.undoManager
            else {
                return
            }

            stopObservingUndoChanges()
            observedTextView = textView
            observedScrollView = scrollView
            observedUndoManager = controller.undoManager
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(undoManagerDidChange),
                name: Notification.Name.NSUndoManagerDidUndoChange,
                object: controller.undoManager
            )
            if let scrollView {
                scrollView.contentView.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(clipViewFrameDidChange),
                    name: NSView.frameDidChangeNotification,
                    object: scrollView.contentView
                )
                resizeDocumentView(textView)
            }
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

        @objc private func clipViewFrameDidChange(_ notification: Notification) {
            guard let textView = observedTextView else { return }
            resizeDocumentView(textView)
        }

        private func synchronizeText(from textView: NSTextView) {
            parent.text = textView.string
            parent.controller.refresh()
            highlightIfNeeded(textView)
            resizeDocumentView(textView)
        }

        func highlightIfNeeded(_ textView: NSTextView) {
            guard
                highlightedText != textView.string || highlightedLanguage != parent.language
                    || !wasHighlighted
            else { return }

            let source = textView.string
            let language = parent.language
            let languageChanged = highlightedLanguage != language || !wasHighlighted
            highlightedText = source
            highlightedLanguage = language
            wasHighlighted = true
            highlightTask?.cancel()
            highlightRequestID += 1

            guard let language else {
                ScriptSyntaxHighlighter.clear(textView)
                return
            }

            switch language {
            case .shell(let dialect):
                ScriptSyntaxHighlighter.apply(
                    ShellSyntaxHighlighter.tokens(in: source, dialect: dialect),
                    to: textView
                )
            case .python, .javascript, .ruby:
                if languageChanged {
                    ScriptSyntaxHighlighter.clear(textView)
                }
                scheduleTreeSitterHighlighting(source, language: language, textView: textView)
            }
        }

        private func scheduleTreeSitterHighlighting(
            _ source: String,
            language: ScriptLanguage,
            textView: NSTextView
        ) {
            let requestID = highlightRequestID
            highlightTask = Task { @MainActor [weak self, weak textView] in
                do {
                    try await Task.sleep(for: .milliseconds(60))
                    let tokens = try await TreeSitterSyntaxHighlighter.shared.tokens(
                        in: source,
                        language: language
                    )
                    try Task.checkCancellation()

                    guard
                        let self,
                        let textView,
                        self.highlightRequestID == requestID,
                        self.observedTextView === textView,
                        textView.string == source,
                        self.parent.language == language
                    else {
                        return
                    }

                    ScriptSyntaxHighlighter.apply(tokens, to: textView)
                    self.highlightTask = nil
                } catch {
                    // Cancellation and unavailable grammar resources both leave plain text usable.
                }
            }
        }

        func resizeDocumentView(_ textView: NSTextView) {
            guard let scrollView = observedScrollView else { return }
            ScriptTextEditor.resizeDocumentView(textView, in: scrollView)
        }

        private func stopObservingUndoChanges() {
            highlightTask?.cancel()
            highlightTask = nil
            highlightRequestID += 1
            if let observedUndoManager {
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
            }
            if let observedScrollView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.frameDidChangeNotification,
                    object: observedScrollView.contentView
                )
            }
            self.observedUndoManager = nil
            observedTextView = nil
            observedScrollView = nil
            highlightedText = nil
            highlightedLanguage = nil
            wasHighlighted = false
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.controller.undoManager
        }
    }
}
