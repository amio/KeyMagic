import FoundationModels
import SwiftUI

private let scriptHotkeyColumnWidth: CGFloat = 97

/// The Scripts settings view: manages script-type shortcuts.
/// Fixed two-panel layout: 240px list on the left, edit panel on the right.
struct ScriptsView: View {
    @Environment(ShortcutStore.self) private var store
    @Environment(HotkeyService.self) private var hotkeyService
    @Environment(ScriptLogStore.self) private var logStore
    @Environment(ShortcutExecutor.self) private var shortcutExecutor

    @State private var selectedID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var deletingShortcutID: UUID?
    @State private var showingLogs = false
    @State private var logsShortcutID: UUID?
    @State private var editorRunIDs: [UUID: UUID] = [:]
    @State private var recordingShortcutID: UUID?

    /// Only script-type shortcuts (runScript / runScriptFile).
    private var scriptShortcuts: [Shortcut] {
        store.shortcuts.filter { shortcut in
            switch shortcut.action {
            case .runScript, .runScriptFile: return true
            case .launchApp: return false
            }
        }
    }

    /// The currently selected shortcut (derived from selectedID).
    private var selectedShortcut: Shortcut? {
        scriptShortcuts.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: script list (fixed 260px)
            scriptListPanel
                .frame(width: 260)

            Divider()

            // Right: edit panel (fills remaining width)
            editPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Scripts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addNewScript()
                } label: {
                    Label("Add Script", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingLogs) {
            if let logsShortcutID {
                ScriptLogsView(
                    logs: logStore.recentLogs(for: logsShortcutID),
                    scriptName: store.shortcuts.first { $0.id == logsShortcutID }?.name ?? "Deleted Script"
                )
            }
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

    // MARK: - Left Panel: Script List

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
                // Header
                ListTableHeader(trailingPadding: 8) {
                    Text("Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Hotkey")
                        .frame(width: scriptHotkeyColumnWidth, alignment: .leading)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(scriptShortcuts.enumerated()), id: \.element.id) { index, shortcut in
                            ScriptRow(
                                shortcut: shortcut,
                                isOdd: !index.isMultiple(of: 2),
                                isSelected: selectedID == shortcut.id,
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
                            .onTapGesture { selectedID = shortcut.id }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Right Panel: Edit / Placeholder

    @ViewBuilder
    private var editPanel: some View {
        if let shortcut = selectedShortcut {
            ScriptEditView(
                shortcut: shortcut,
                isRunning: isEditorRunActive(for: shortcut.id),
                hasLogs: !logStore.recentLogs(for: shortcut.id).isEmpty,
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
                }
            )
            .id(shortcut.id)
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "cursorarrow.click")
            } description: {
                Text("Select a script from the list to edit, or add a new one.")
            }
        }
    }

    // MARK: - Actions

    private func addNewScript() {
        let newShortcut = Shortcut(
            name: "Untitled Script",
            keyCombo: nil,
            action: .runScript(script: "", shell: .zsh),
            isEnabled: true
        )
        store.add(newShortcut)
        hotkeyService.restart(store: store)
        selectedID = newShortcut.id
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

    private func showLogs(for shortcutID: UUID) {
        logsShortcutID = shortcutID
        showingLogs = true
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
        if selectedID == id {
            selectedID = nil
        }
        store.remove(id: id)
        hotkeyService.restart(store: store)
        editorRunIDs[id] = nil
    }
}

// MARK: - Script Row (compact: name + hotkey cell with recording support)

private struct ScriptRow: View {
    let shortcut: Shortcut
    let isOdd: Bool
    let isSelected: Bool
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onRecordKey: (KeyCombo) -> Void
    let onCancelRecording: () -> Void
    let onClearHotkey: () -> Void
    var checkConflict: ((KeyCombo) -> Bool)?

    var body: some View {
        ListRowContainer(
            isOdd: isOdd,
            accentBackground: isSelected ? Color.accentColor.opacity(0.12) : .clear,
            verticalPadding: 6,
            trailingPadding: 8
        ) {
            // Name + availability warning
            HStack(spacing: 6) {
                Text(shortcut.name)
                    .lineLimit(1)
                    .fontWeight(.medium)
                    .font(.callout)

                // Warn when a script file doesn't exist on this Mac (e.g. synced from another device).
                if !shortcut.isAvailableOnThisDevice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Script file not found on this Mac")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hotkey cell with recording / edit / delete
            HotkeyCellView(
                keyCombo: shortcut.keyCombo,
                isRecording: isRecording,
                onStartRecording: onStartRecording,
                onRecordKey: onRecordKey,
                onCancelRecording: onCancelRecording,
                onClearHotkey: onClearHotkey,
                checkConflict: checkConflict
            )
            .frame(width: scriptHotkeyColumnWidth, alignment: .leading)
        }
        .opacity(shortcut.isEnabled ? 1.0 : 0.6)
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
    private var savedDraft: ScriptEditorDraft?

    var hasUnsavedChanges: Bool {
        guard let savedDraft else { return false }
        return draft != savedDraft
    }

    mutating func load(_ shortcut: Shortcut) {
        let loadedDraft = ScriptEditorDraft(shortcut: shortcut)
        draft = loadedDraft
        savedDraft = loadedDraft
    }

    mutating func markSaved() {
        savedDraft = draft
    }
}

struct ScriptEditView: View {
    let shortcut: Shortcut
    let isRunning: Bool
    let hasLogs: Bool
    let onSave: (Shortcut) -> Void
    let onRun: () -> Void
    let onShowLog: () -> Void
    let onDelete: () -> Void

    @State private var draftState = ScriptEditorDraftState()
    @State private var autosaveTask: Task<Void, Never>?
    @State private var editorController = ScriptTextEditorController()

    // AI generation state
    @State private var isGenerating = false
    @State private var generationError: String?

    private var isValid: Bool {
        draftState.draft.isValid
    }

    /// Whether the on-device Foundation Models framework is usable on this system.
    private var isAIAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.availability == .available
    }

    /// Human-readable reason when AI generation is unavailable.
    private var aiUnavailableReason: String? {
        guard #available(macOS 26, *) else {
            return "Requires macOS 26 or later"
        }
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
        VStack(spacing: 0) {
            // Header: title + action buttons
            headerBar

            Divider()

            // Form body. Keep the metadata grouped in one row so the editor remains the
            // visual focus without shrinking the controls or their labels.
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    nameField
                        .frame(maxWidth: .infinity)
                    shellPicker
                        .frame(width: 240, alignment: .trailing)
                }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFrom(shortcut) }
        .onDisappear { flushAutosave() }
        .onChange(of: draftState.draft) { scheduleAutosave() }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text("Edit Script")
                .font(.headline)

            saveStatus

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .frame(minWidth: headerActionMinWidth)
            .controlSize(.regular)
            .help("Delete this script")

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // Keep header action buttons aligned and stable in width.
    private var headerActionMinWidth: CGFloat { 60 }

    @ViewBuilder
    private var saveStatus: some View {
        if draftState.hasUnsavedChanges {
            if isValid {
                Label("Unsaved changes", systemImage: "clock")
                    .foregroundStyle(.secondary)
            } else {
                Label("Name required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Form Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. Deploy Script", text: $draftState.draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

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
            ScriptTextEditor(text: $draftState.draft.scriptContent, controller: editorController)
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
            // AI Generate button — disabled with an instant tooltip when unavailable
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
            .immediateHelp(aiUnavailableReason ?? "Generate script from comments using Apple Intelligence")

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
            try? await Task.sleep(for: .seconds(2))
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
        let draft = draftState.draft
        let action = ShortcutAction.runScript(script: draft.scriptContent, shell: draft.shellType)
        var updated = shortcut
        updated.name = draft.name
        updated.action = action
        draftState.markSaved()
        onSave(updated)
    }

    private func run() {
        flushAutosave()
        onRun()
    }

    private func loadFrom(_ shortcut: Shortcut) {
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

        guard #available(macOS 26, *) else { return }
        generateWithModel()
    }

    /// Calls the on-device Foundation Model to generate script code from the user's comments.
    @available(macOS 26, *)
    private func generateWithModel() {
        let shell = draftState.draft.shellType
        let input = draftState.draft.scriptContent
        isGenerating = true
        generationError = nil

        Task {
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
                guard draftState.draft.scriptContent == input else {
                    generationError = "Script changed while generating. Generate again to use the latest content."
                    isGenerating = false
                    return
                }
                editorController.replaceAll(with: response.content, actionName: "Generate Script")
            } catch {
                generationError = error.localizedDescription
            }
            isGenerating = false
        }
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
