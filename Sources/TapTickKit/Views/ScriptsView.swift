import AppKit
import FoundationModels
import SwiftUI

private struct ScriptLogsPresentation: Identifiable {
    let shortcutID: UUID

    var id: UUID { shortcutID }
}

/// Owns the Scripts directory column and its list-specific interactions.
struct ScriptsDirectoryView: View {
    @Environment(ShortcutStore.self) private var store
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var selection: UUID?
    @Binding var nameSelectionRequestID: UUID?

    @State private var recordingShortcutID: UUID?
    @FocusState private var isScriptListFocused: Bool

    /// Only script-type shortcuts (runScript / runScriptFile).
    private var scriptShortcuts: [Shortcut] {
        store.shortcuts.filter { shortcut in
            switch shortcut.action {
            case .runScript, .runScriptFile: return true
            case .launchApp: return false
            }
        }
    }

    var body: some View {
        scriptListPanel
            .onChange(of: selection) { _, shortcutID in
                if let requestID = nameSelectionRequestID {
                    guard requestID != shortcutID else { return }
                    nameSelectionRequestID = nil
                }
                restoreScriptListFocus(afterSelecting: shortcutID)
            }
            .toolbar {
                ToolbarSpacer(.flexible)

                ToolbarItem(placement: .automatic) {
                    Button("Add Script", systemImage: "plus", action: addNewScript)
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Add Script (⌘N)")
                }
            }
    }

    // MARK: - Script List

    @ViewBuilder
    private var scriptListPanel: some View {
        VStack(spacing: 0) {
            if scriptShortcuts.isEmpty {
                Spacer()
                ContentUnavailableView {
                    Label("No Scripts", systemImage: "terminal")
                } description: {
                    Text("Add a script to get started.")
                } actions: {
                    Button("Add Script") { addNewScript() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Spacer()
            } else {
                List(scriptShortcuts, selection: $selection) { shortcut in
                    ScriptRow(
                        shortcut: shortcut,
                        isSelected: selection == shortcut.id,
                        usesEmphasizedSelection: selection == shortcut.id && isScriptListFocused,
                        isRecording: recordingShortcutID == shortcut.id,
                        onStartRecording: {
                            recordingShortcutID = shortcut.id
                        },
                        onRecordKey: { combo in
                            bindHotkey(combo, to: shortcut)
                            recordingShortcutID = nil
                        },
                        onCancelRecording: {
                            recordingShortcutID = nil
                        },
                        onClearHotkey: {
                            clearHotkey(for: shortcut)
                        },
                        checkConflict: { combo in
                            hotkeyService.hasConflict(
                                keyCombo: combo,
                                excludingShortcutID: shortcut.id
                            )
                        }
                    )
                    .tag(shortcut.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .focused($isScriptListFocused)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Keep native list focus after its selection transaction without overriding later editor focus.
    private func restoreScriptListFocus(afterSelecting shortcutID: UUID?) {
        guard let shortcutID else { return }

        Task { @MainActor in
            await Task.yield()
            guard
                selection == shortcutID,
                nameSelectionRequestID != shortcutID,
                !isScriptListFocused
            else { return }
            isScriptListFocused = true
        }
    }

    private func addNewScript() {
        let shortcutID = createNewScript(
            in: store,
            hotkeyService: hotkeyService
        )
        nameSelectionRequestID = shortcutID
        selection = shortcutID
    }

    private func bindHotkey(_ combo: KeyCombo, to shortcut: Shortcut) {
        var updated = shortcut
        updated.keyCombo = combo
        store.update(updated)
        hotkeyService.restart(store: store)
    }

    private func clearHotkey(for shortcut: Shortcut) {
        var updated = shortcut
        updated.keyCombo = nil
        store.update(updated)
        hotkeyService.restart(store: store)
    }
}

@MainActor
private func createNewScript(
    in store: ShortcutStore,
    hotkeyService: HotkeyService
) -> UUID {
    let newShortcut = Shortcut(
        name: "Untitled Script",
        keyCombo: nil,
        action: .runScript(script: "", shell: .zsh),
        isEnabled: true
    )
    store.add(newShortcut)
    hotkeyService.restart(store: store)
    return newShortcut.id
}

private enum ScriptEditorSaveStatus: Equatable {
    case saved
    case unsaved
    case nameRequired
}

/// Owns the selected script's editor lifecycle and detail-only presentations.
struct ScriptDetailView: View {
    @Environment(ShortcutStore.self) private var store
    @Environment(HotkeyService.self) private var hotkeyService
    @Environment(ScriptLogStore.self) private var logStore
    @Environment(ShortcutExecutor.self) private var shortcutExecutor

    @Binding var selection: UUID?
    @Binding var nameSelectionRequestID: UUID?

    @State private var showingDeleteConfirmation = false
    @State private var deletingShortcutID: UUID?
    @State private var logsPresentation: ScriptLogsPresentation?
    @State private var editorRunIDs: [UUID: UUID] = [:]

    private var selectedShortcut: Shortcut? {
        guard let shortcut = store.shortcuts.first(where: { $0.id == selection }) else {
            return nil
        }

        switch shortcut.action {
        case .runScript, .runScriptFile:
            return shortcut
        case .launchApp:
            return nil
        }
    }

    var body: some View {
        editPanel
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(item: $logsPresentation) { presentation in
                ScriptLogsView(
                    logs: logStore.recentLogs(for: presentation.shortcutID),
                    scriptName: store.shortcuts.first {
                        $0.id == presentation.shortcutID
                    }?.name ?? "Deleted Script"
                )
            }
            .confirmationDialog(
                "Delete Script?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = deletingShortcutID {
                        deleteShortcut(id: id)
                        deletingShortcutID = nil
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
    }

    @ViewBuilder
    private var editPanel: some View {
        if let shortcut = selectedShortcut {
            ScriptEditView(
                shortcut: shortcut,
                isRunning: isEditorRunActive(for: shortcut.id),
                hasLogs: !logStore.recentLogs(for: shortcut.id).isEmpty,
                nameSelectionRequestID: nameSelectionRequestID,
                onSave: { updated in
                    store.updateScript(updated)
                },
                onRun: {
                    run(shortcutID: shortcut.id)
                },
                onShowLog: {
                    showLogs(for: shortcut.id)
                },
                onDelete: {
                    deletingShortcutID = shortcut.id
                    showingDeleteConfirmation = true
                },
                onNameSelectionRequestHandled: {
                    guard nameSelectionRequestID == shortcut.id else { return }
                    nameSelectionRequestID = nil
                }
            )
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "cursorarrow.click")
            } description: {
                Text("Select a script from the list to edit, or add a new one.")
            }
        }
    }

    private func showLogs(for shortcutID: UUID) {
        logsPresentation = ScriptLogsPresentation(shortcutID: shortcutID)
    }

    private func run(shortcutID: UUID) {
        guard let runID = shortcutExecutor.execute(shortcutID: shortcutID) else { return }
        editorRunIDs[shortcutID] = runID
    }

    private func isEditorRunActive(for shortcutID: UUID) -> Bool {
        guard let runID = editorRunIDs[shortcutID] else { return false }
        return shortcutExecutor.isRunning(runID: runID)
    }

    private func deleteShortcut(id: UUID) {
        if selection == id {
            selection = nil
        }
        store.remove(id: id)
        hotkeyService.restart(store: store)
        editorRunIDs[id] = nil
    }
}

// MARK: - Script Row (compact: name + hotkey cell with recording support)

private struct ScriptRow: View {
    let shortcut: Shortcut
    let isSelected: Bool
    let usesEmphasizedSelection: Bool
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecordKey: (KeyCombo) -> Void
    let onCancelRecording: () -> Void
    let onClearHotkey: () -> Void
    var checkConflict: ((KeyCombo) -> Bool)?

    @State private var isHovered = false

    private var showsHotkeyControl: Bool {
        shortcut.keyCombo != nil || isRecording || isSelected || isHovered
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(shortcut.name)
                    .lineLimit(1)
                    .fontWeight(.medium)

                if !shortcut.isAvailableOnThisDevice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Script file not found on this Mac")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsHotkeyControl {
                HotkeyBindingControl(
                    keyCombo: shortcut.keyCombo,
                    isRecording: isRecording,
                    onStartRecording: onStartRecording,
                    onRecordKey: onRecordKey,
                    onCancelRecording: onCancelRecording,
                    onClearHotkey: onClearHotkey,
                    checkConflict: checkConflict,
                    emptyTitle: "Set Hotkey",
                    usesEmphasizedAppearance: usesEmphasizedSelection
                )
            }
        }
        .frame(height: 24)
        .opacity(shortcut.isEnabled ? 1.0 : 0.6)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Script Edit View (always-visible right panel)

struct ScriptEditorDraft: Equatable {
    var name = ""
    var scriptContent = ""
    var shellType: ShortcutAction.ShellType = .zsh

    init() {}

    init(shortcut: Shortcut) {
        name = shortcut.name

        switch shortcut.action {
        case .runScript(let script, let shell):
            scriptContent = script
            shellType = shell
        case .runScriptFile(let path, let shell):
            scriptContent = "# Script file: \(path)\n"
            shellType = shell
        case .launchApp:
            break
        }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Derives dirty state from the current draft and its persisted baseline.
struct ScriptEditorDraftState {
    var draft = ScriptEditorDraft()
    private(set) var loadedShortcut: Shortcut?
    private var savedDraft: ScriptEditorDraft?

    init() {}

    init(shortcut: Shortcut) {
        load(shortcut)
    }

    var hasUnsavedChanges: Bool {
        guard let savedDraft else { return false }
        return draft != savedDraft
    }

    var loadedShortcutID: UUID? {
        loadedShortcut?.id
    }

    mutating func load(_ shortcut: Shortcut) {
        let loadedDraft = ScriptEditorDraft(shortcut: shortcut)
        loadedShortcut = shortcut
        draft = loadedDraft
        savedDraft = loadedDraft
    }

    func shortcutWithCurrentDraft() -> Shortcut? {
        guard var updated = loadedShortcut else { return nil }
        updated.name = draft.name
        updated.action = .runScript(script: draft.scriptContent, shell: draft.shellType)
        return updated
    }

    mutating func markSaved() {
        if let updated = shortcutWithCurrentDraft() {
            loadedShortcut = updated
        }
        savedDraft = draft
    }
}

private struct ScriptDetailHeader: View {
    private struct CompactStatusLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon
                configuration.title
            }
        }
    }

    private struct NameSelectionTaskID: Equatable {
        let shortcutID: UUID
        let requestID: UUID?
    }

    let shortcutID: UUID
    @Binding var name: String
    let saveStatus: ScriptEditorSaveStatus
    let nameSelectionRequestID: UUID?
    let onSubmit: () -> Void
    let onNameSelectionRequestHandled: () -> Void

    @State private var isNameHovered = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .contentShape(.rect)
                .gesture(WindowDragGesture())

            nameField

            saveStatusLabel
        }
    }

    private var nameField: some View {
        Text(name.isEmpty ? " " : name)
            .font(.headline)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 50, alignment: .leading)
            .overlay(alignment: .leading) {
                TextField("Script Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .focused($isNameFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .onSubmit { onSubmit() }
                    .accessibilityLabel("Script Name")
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(nameBorderColor, lineWidth: 1)
                    .opacity(isNameHovered || isNameFocused ? 1 : 0)
            }
            .onHover { isNameHovered = $0 }
            .task(
                id: NameSelectionTaskID(
                    shortcutID: shortcutID,
                    requestID: nameSelectionRequestID
                )
            ) {
                await selectNameForNewScriptIfNeeded()
            }
    }

    private var nameBorderColor: Color {
        isNameFocused ? .accentColor : Color(nsColor: .separatorColor)
    }

    private var saveStatusLabel: some View {
        Group {
            switch saveStatus {
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .unsaved:
                Label("Unsaved changes", systemImage: "clock")
                    .foregroundStyle(.secondary)
            case .nameRequired:
                Label("Name required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .labelStyle(CompactStatusLabelStyle())
    }

    @MainActor
    private func selectNameForNewScriptIfNeeded() async {
        guard nameSelectionRequestID == shortcutID else { return }

        isNameFocused = true
        await Task.yield()

        guard !Task.isCancelled, nameSelectionRequestID == shortcutID else { return }
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
        onNameSelectionRequestHandled()
    }
}

struct ScriptEditView: View {
    let shortcut: Shortcut
    let isRunning: Bool
    let hasLogs: Bool
    let nameSelectionRequestID: UUID?
    let onSave: (Shortcut) -> Void
    let onRun: () -> Void
    let onShowLog: () -> Void
    let onDelete: () -> Void
    let onNameSelectionRequestHandled: () -> Void

    @State private var draftState: ScriptEditorDraftState
    @State private var autosaveTask: Task<Void, Never>?
    @State private var editorController = ScriptTextEditorController()

    // AI generation state
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationRequestID: UUID?

    init(
        shortcut: Shortcut,
        isRunning: Bool,
        hasLogs: Bool,
        nameSelectionRequestID: UUID?,
        onSave: @escaping (Shortcut) -> Void,
        onRun: @escaping () -> Void,
        onShowLog: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onNameSelectionRequestHandled: @escaping () -> Void
    ) {
        self.shortcut = shortcut
        self.isRunning = isRunning
        self.hasLogs = hasLogs
        self.nameSelectionRequestID = nameSelectionRequestID
        self.onSave = onSave
        self.onRun = onRun
        self.onShowLog = onShowLog
        self.onDelete = onDelete
        self.onNameSelectionRequestHandled = onNameSelectionRequestHandled
        _draftState = State(initialValue: ScriptEditorDraftState(shortcut: shortcut))
    }

    private var isValid: Bool {
        draftState.draft.isValid
    }

    private var currentSaveStatus: ScriptEditorSaveStatus {
        guard draftState.hasUnsavedChanges else { return .saved }
        return isValid ? .unsaved : .nameRequired
    }

    /// Whether the on-device Foundation Models framework is usable on this system.
    private var isAIAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Human-readable reason when AI generation is unavailable.
    private var aiUnavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac does not support Apple Intelligence"
            case .modelNotReady:
                return "Apple Intelligence model is not ready — check Settings"
            case .appleIntelligenceNotEnabled:
                return "Enable Apple Intelligence in System Settings"
            @unknown default:
                return "Apple Intelligence is not available"
            }
        @unknown default:
            return "Apple Intelligence is not available"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            shellPicker
                .frame(width: 240, alignment: .leading)

            scriptEditor

            // Inline error banner for AI generation failures
            if let error = generationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { generationError = nil }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                detailHeader
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.flexible)

            ToolbarItem(placement: .automatic) {
                deleteButton
            }
        }
        .onDisappear {
            flushAutosave()
            cancelGeneration()
        }
        .onChange(of: shortcut.id) {
            switchTo(shortcut)
        }
        .onChange(of: draftState.draft) { scheduleAutosave() }
    }

    // MARK: - Header

    private var detailHeader: some View {
        ScriptDetailHeader(
            shortcutID: shortcut.id,
            name: $draftState.draft.name,
            saveStatus: currentSaveStatus,
            nameSelectionRequestID: nameSelectionRequestID,
            onSubmit: flushAutosave,
            onNameSelectionRequestHandled: onNameSelectionRequestHandled
        )
    }

    private var deleteButton: some View {
        Button("Delete Script", systemImage: "trash", role: .destructive) {
            onDelete()
        }
        .labelStyle(.iconOnly)
        .help("Delete Script")
        .accessibilityLabel("Delete Script")
    }

    // MARK: - Form Fields

    private var shellPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shell")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $draftState.draft.shellType) {
                ForEach(ShortcutAction.ShellType.allCases, id: \.self) { shell in
                    Text(shell.displayName).tag(shell)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var scriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Keep editing controls on the left and execution actions on the right.
            HStack(alignment: .center) {
                Text("Script")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                undoRedoButtons
                Spacer()
                editorActionButtons
            }
            ScriptTextEditor(
                text: $draftState.draft.scriptContent,
                shell: draftState.draft.shellType,
                controller: editorController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity)
    }

    private var undoRedoButtons: some View {
        HStack(spacing: 2) {
            Button {
                editorController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!editorController.canUndo)
            .help("Undo (⌘Z)")

            Button {
                editorController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!editorController.canRedo)
            .help("Redo (⇧⌘Z)")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    /// Generate and Run buttons sitting above the editor's top-right corner.
    private var editorActionButtons: some View {
        HStack(spacing: 6) {
            // AI Generate button
            Button {
                handleGenerate()
            } label: {
                ZStack {
                    Label("Generate", systemImage: "sparkles")
                        .opacity(isGenerating ? 0 : 1)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isGenerating ? 1 : 0)
                }
            }
            .disabled(!isAIAvailable || isGenerating || isRunning)
            .controlSize(.small)
            .help(aiUnavailableReason ?? "Generate script from comments using Apple Intelligence")

            // Run button — dispatches the stored shortcut through the normal trigger path
            Button {
                run()
            } label: {
                ZStack {
                    Label("Run", systemImage: "play.fill")
                        .opacity(isRunning ? 0 : 1)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isRunning ? 1 : 0)
                }
            }
            .disabled(draftState.draft.scriptContent.isEmpty || isRunning)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Test run this script")

            // Logs — reviews the most recent script executions
            Button {
                onShowLog()
            } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(!hasLogs)
            .controlSize(.small)
            .help("Review the \(ScriptLogStore.recentLogLimit) most recent script executions")
        }
    }

    // MARK: - Logic

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard draftState.hasUnsavedChanges, isValid else { return }

        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func flushAutosave() {
        autosaveTask?.cancel()
        guard draftState.hasUnsavedChanges, isValid else { return }
        save()
    }

    private func save() {
        autosaveTask?.cancel()
        guard let updated = draftState.shortcutWithCurrentDraft() else { return }
        draftState.markSaved()
        onSave(updated)
    }

    private func run() {
        flushAutosave()
        onRun()
    }

    private func switchTo(_ shortcut: Shortcut) {
        guard draftState.loadedShortcutID != shortcut.id else { return }
        flushAutosave()
        cancelGeneration()
        generationError = nil
        autosaveTask?.cancel()
        draftState.load(shortcut)
        editorController.reset()
    }

    // MARK: - AI Generation

    /// Inserts a starter comment template when the editor is empty,
    /// otherwise sends the current content to the on-device model for code generation.
    private func handleGenerate() {
        generationError = nil

        // Empty editor: insert a starter template so the user knows how to use the feature.
        let trimmed = draftState.draft.scriptContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            editorController.replaceAll(
                with: scriptTemplateForShell(draftState.draft.shellType),
                actionName: "Insert Template"
            )
            return
        }

        generateWithModel()
    }

    /// Calls the on-device Foundation Model to generate script code from the user's comments.
    private func generateWithModel() {
        generationTask?.cancel()

        let shell = draftState.draft.shellType
        let input = draftState.draft.scriptContent
        let requestID = UUID()
        generationRequestID = requestID
        isGenerating = true
        generationError = nil

        generationTask = Task { @MainActor in
            defer {
                if generationRequestID == requestID {
                    isGenerating = false
                    generationTask = nil
                    generationRequestID = nil
                }
            }

            do {
                let session = LanguageModelSession(
                    instructions: """
                        You are a shell script generator. The user provides comments \
                        describing what they want the script to do. Generate ONLY the \
                        script code. Do NOT wrap output in markdown code fences. Preserve \
                        the user's original comments in-place and add implementation code \
                        right after each relevant comment block. Use \(shell.displayName) \
                        syntax. Output must be valid, runnable shell code.
                        """
                )

                let prompt = """
                    Based on the following commented instructions, generate a complete \
                    \(shell.displayName) script:

                    \(input)
                    """

                let response = try await session.respond(to: prompt)
                try Task.checkCancellation()
                guard draftState.draft.scriptContent == input else {
                    generationError = "Script changed while generating. Generate again to use the latest content."
                    return
                }
                editorController.replaceAll(with: response.content, actionName: "Generate Script")
            } catch {
                if !Task.isCancelled {
                    generationError = error.localizedDescription
                }
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationRequestID = nil
        isGenerating = false
    }

    /// Returns a starter comment template that teaches the user how to use AI generation.
    private func scriptTemplateForShell(_ shell: ShortcutAction.ShellType) -> String {
        let shebang = "#!\(shell.rawValue)"
        return """
            \(shebang)

            # Describe what you want this script to do.
            # Write your instructions as comments, then click "Generate" again
            # to let Apple Intelligence generate the code for you.
            #
            # Example:
            #   List all .log files in /var/log that are older than 7 days,
            #   then print their total size in human-readable format.

            """
    }
}

// MARK: - Script Logs View

private struct ScriptLogsView: View {
    let logs: [ScriptExecutionLog]
    let scriptName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(scriptName) Logs")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Run a script to create an execution log.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                            ScriptLogRow(
                                log: log,
                                showsDivider: index < logs.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

private struct ScriptLogRow: View {
    let log: ScriptExecutionLog
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: log.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(log.succeeded ? .green : .red)
                Text(
                    log.timestamp,
                    format: .dateTime.year().month().day().hour().minute().second()
                )
                .font(.headline)
                .monospacedDigit()
                Spacer()
                Text(log.durationText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(log.displayText)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
            }
        }
    }
}
