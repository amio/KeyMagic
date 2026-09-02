import AppKit
import FoundationModels
import SwiftUI

private struct ScriptLogsPresentation: Identifiable {
    let shortcutID: UUID

    var id: UUID { shortcutID }
}

private struct OpenScriptsDirectoryButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "folder")
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.09 : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open Scripts Folder")
        .accessibilityLabel("Open Scripts Folder")
    }
}

/// Owns the Scripts directory column and its list-specific interactions.
struct ScriptsDirectoryView: View {
    @Environment(ShortcutStore.self) private var store
    @Environment(HotkeyService.self) private var hotkeyService

    @Binding var selection: UUID?
    @Binding var nameSelectionRequestID: UUID?

    @State private var recordingShortcutID: UUID?
    @State private var directoryError: String?
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

    private var scriptShortcutIDs: [UUID] {
        scriptShortcuts.map(\.id)
    }

    private var resolvedSelection: UUID? {
        guard let selection, scriptShortcutIDs.contains(selection) else {
            return scriptShortcutIDs.first
        }
        return selection
    }

    var body: some View {
        scriptListPanel
            .alert(
                "Scripts Error",
                isPresented: Binding(
                    get: { directoryError != nil },
                    set: { if !$0 { directoryError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(directoryError ?? "")
            }
            .onChange(of: scriptShortcutIDs, initial: true) { _, shortcutIDs in
                ensureValidSelection(in: shortcutIDs)
            }
            .onChange(of: store.scriptDirectoryIssue, initial: true) { _, issue in
                if let issue { directoryError = issue }
            }
            .onChange(of: selection) { _, shortcutID in
                if let requestID = nameSelectionRequestID {
                    guard requestID != shortcutID else { return }
                    nameSelectionRequestID = nil
                }
                restoreScriptListFocus(afterSelecting: shortcutID)
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 4) {
                        SettingsToolbarTitle(title: "Scripts")
                        OpenScriptsDirectoryButton {
                            openScriptsDirectory()
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)

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
            } else if let fallbackSelection = scriptShortcutIDs.first {
                List(
                    scriptShortcuts,
                    selection: listSelection(fallback: fallbackSelection)
                ) { shortcut in
                    ScriptRow(
                        shortcut: shortcut,
                        isSelected: resolvedSelection == shortcut.id,
                        usesEmphasizedSelection: resolvedSelection == shortcut.id && isScriptListFocused,
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

    /// Adapt the directory's empty-state-capable selection to SwiftUI's
    /// non-optional List selection API while rows exist.
    private func listSelection(fallback: UUID) -> Binding<UUID> {
        Binding(
            get: { resolvedSelection ?? fallback },
            set: { proposedSelection in
                selection = proposedSelection
            }
        )
    }

    private func ensureValidSelection(in shortcutIDs: [UUID]) {
        guard let selection, shortcutIDs.contains(selection) else {
            self.selection = shortcutIDs.first
            return
        }
    }

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
        do {
            let shortcutID = try store.createScript()
            hotkeyService.restart(store: store)
            nameSelectionRequestID = shortcutID
            selection = shortcutID
        } catch {
            directoryError = error.localizedDescription
        }
    }

    private func openScriptsDirectory() {
        do {
            let directoryURL = try store.prepareScriptsDirectory()
            guard NSWorkspace.shared.open(directoryURL) else {
                directoryError = "Finder could not open the Scripts folder."
                return
            }
        } catch {
            directoryError = error.localizedDescription
        }
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

private enum ScriptEditorSaveStatus: Equatable {
    case saved(opacity: Double)
    case nameRequired
    case error(String)
}

/// Owns the selected script's editor lifecycle and detail-only presentations.
struct ScriptDetailView: View {
    @Environment(ShortcutStore.self) private var store
    @Environment(HotkeyService.self) private var hotkeyService
    @Environment(ScriptLogStore.self) private var logStore
    @Environment(ShortcutExecutor.self) private var shortcutExecutor
    @Environment(MenuBarTextController.self) private var menuBarTextController

    @Binding var selection: UUID?
    @Binding var nameSelectionRequestID: UUID?

    @State private var showingDeleteConfirmation = false
    @State private var showingMenuBarUsageAlert = false
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
            .alert("Script Is Used in Menu Bar", isPresented: $showingMenuBarUsageAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Remove this script from Menu Bar settings before deleting it."
                )
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
                    try store.updateScript(updated)
                },
                onRun: runSelectedShortcut,
                onShowLog: {
                    showLogs(for: shortcut.id)
                },
                onDelete: {
                    requestDeletion(of: shortcut.id)
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

    /// Resolve the target when the command fires because SwiftUI can retain the prior
    /// detail button's keyboard action during a NavigationSplitView selection update.
    private func runSelectedShortcut() {
        guard let shortcutID = selectedShortcut?.id else { return }
        guard let runID = shortcutExecutor.execute(shortcutID: shortcutID) else { return }
        editorRunIDs[shortcutID] = runID
    }

    private func isEditorRunActive(for shortcutID: UUID) -> Bool {
        guard let runID = editorRunIDs[shortcutID] else { return false }
        return shortcutExecutor.isRunning(runID: runID)
    }

    private func deleteShortcut(id: UUID) {
        guard !menuBarTextController.usesScript(id: id) else {
            showingMenuBarUsageAlert = true
            return
        }

        if selection == id {
            selection = selectionAfterRemoving(id)
        }
        store.remove(id: id)
        hotkeyService.restart(store: store)
        editorRunIDs[id] = nil
    }

    private func requestDeletion(of id: UUID) {
        guard !menuBarTextController.usesScript(id: id) else {
            showingMenuBarUsageAlert = true
            return
        }

        deletingShortcutID = id
        showingDeleteConfirmation = true
    }

    /// Prefer the following script after deletion, falling back to the previous one.
    private func selectionAfterRemoving(_ removedID: UUID) -> UUID? {
        let scriptIDs = store.shortcuts.compactMap { shortcut -> UUID? in
            switch shortcut.action {
            case .runScript, .runScriptFile: shortcut.id
            case .launchApp: nil
            }
        }
        guard let removedIndex = scriptIDs.firstIndex(of: removedID) else {
            return scriptIDs.first
        }

        let remainingIDs = scriptIDs.filter { $0 != removedID }
        if remainingIDs.indices.contains(removedIndex) {
            return remainingIDs[removedIndex]
        }
        return remainingIDs.last
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

    init() {}

    init(shortcut: Shortcut) {
        name = shortcut.name

        switch shortcut.action {
        case .runScript(let script):
            scriptContent = script
        case .runScriptFile(let path, _):
            scriptContent = "# Legacy script file unavailable: \(path)\n"
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

    func hasPersistedEditorChange(in shortcut: Shortcut) -> Bool {
        guard let savedDraft else { return true }
        return ScriptEditorDraft(shortcut: shortcut) != savedDraft
    }

    mutating func load(_ shortcut: Shortcut) {
        let loadedDraft = ScriptEditorDraft(shortcut: shortcut)
        loadedShortcut = shortcut
        draft = loadedDraft
        savedDraft = loadedDraft
    }

    mutating func updateLoadedMetadata(_ shortcut: Shortcut) {
        guard shortcut.id == loadedShortcut?.id else { return }
        loadedShortcut = shortcut
    }

    func shortcutWithCurrentDraft() -> Shortcut? {
        guard var updated = loadedShortcut else { return nil }
        updated.name = draft.name
        updated.action = .runScript(script: draft.scriptContent)
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
    private enum NameFieldLayout {
        static let visualHorizontalInset: CGFloat = 8
        static let editorTrailingReserve: CGFloat = 4
        static let verticalInset: CGFloat = 4
        static let minimumWidth: CGFloat = 50
    }

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
        // TextField's ideal width undermeasures CJK text in a macOS toolbar. Let Text own
        // the content measurement while the overlaid field retains native editing behavior.
        Text(name.isEmpty ? "Script Name" : name)
            .font(.headline)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                logNameFieldGeometry("text", size: size)
            }
            .hidden()
            .accessibilityHidden(true)
            .padding(.horizontal, NameFieldLayout.visualHorizontalInset)
            .padding(.vertical, NameFieldLayout.verticalInset)
            .frame(minWidth: NameFieldLayout.minimumWidth, alignment: .leading)
            .overlay(alignment: .leading) {
                TextField("Script Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .focused($isNameFocused)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        logNameFieldGeometry("field", size: size)
                    }
                    .padding(.leading, NameFieldLayout.visualHorizontalInset)
                    .padding(
                        .trailing,
                        NameFieldLayout.visualHorizontalInset
                            - NameFieldLayout.editorTrailingReserve
                    )
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                logNameFieldGeometry("border", size: size)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(nameBorderColor, lineWidth: 1)
                    .opacity(isNameHovered || isNameFocused ? 1 : 0)
            }
            .onHover { isNameHovered = $0 }
            .onSubmit { onSubmit() }
            .accessibilityLabel("Script Name")
            .task(
                id: NameSelectionTaskID(
                    shortcutID: shortcutID,
                    requestID: nameSelectionRequestID
                )
            ) {
                await selectNameForNewScriptIfNeeded()
            }
            .fixedSize(horizontal: true, vertical: false)
    }

    private func logNameFieldGeometry(_ role: String, size: CGSize) {
        guard ProcessInfo.processInfo.environment["TAPTICK_TITLE_LAYOUT_DIAGNOSTICS"] == "1"
        else { return }
        print(
            "TITLE_LAYOUT role=\(role) characters=\(name.count) "
                + "width=\(size.width) height=\(size.height)"
        )
    }

    private var nameBorderColor: Color {
        isNameFocused ? .accentColor : Color(nsColor: .separatorColor)
    }

    private var saveStatusLabel: some View {
        Group {
            switch saveStatus {
            case .saved(let opacity):
                Label {
                    Text("Saved")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .opacity(opacity)
                .accessibilityHidden(opacity == 0)
            case .nameRequired:
                Label("Name required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .labelStyle(CompactStatusLabelStyle())
        .lineLimit(1)
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
    let onSave: (Shortcut) throws -> Shortcut
    let onRun: () -> Void
    let onShowLog: () -> Void
    let onDelete: () -> Void
    let onNameSelectionRequestHandled: () -> Void

    @State private var draftState: ScriptEditorDraftState
    @State private var autosaveTask: Task<Void, Never>?
    @State private var savedStatusTask: Task<Void, Never>?
    @State private var editorController = ScriptTextEditorController()
    @State private var saveError: String?
    @State private var savedStatusOpacity = 0.0

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
        onSave: @escaping (Shortcut) throws -> Shortcut,
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
        if let saveError { return .error(saveError) }
        if draftState.hasUnsavedChanges {
            return isValid ? .saved(opacity: 0) : .nameRequired
        }
        return .saved(opacity: savedStatusOpacity)
    }

    private var shebangValidation: ScriptShebang.Validation {
        ScriptShebang.inspect(draftState.draft.scriptContent)
    }

    private var isAddingShebang: Bool {
        draftState.draft.scriptContent.first != "#"
    }

    private var shebangRepairLabel: Text {
        isAddingShebang ? Text("Add Shebang") : Text("Fix Shebang")
    }

    private var shebangRepairHelp: Text {
        if isAddingShebang {
            Text("Add shebang: \(shebangValidation.message)")
        } else {
            Text("Fix shebang: \(shebangValidation.message)")
        }
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
                SettingsToolbarItemLayout {
                    detailHeader
                        .padding(.leading, SettingsLayout.toolbarTitleLeadingPadding)
                }
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.flexible)

            ToolbarItem(placement: .automatic) {
                deleteButton
            }
        }
        .onDisappear {
            flushAutosave()
            savedStatusTask?.cancel()
            cancelGeneration()
        }
        .onChange(of: shortcut) { _, updatedShortcut in
            receiveStoreUpdate(updatedShortcut)
        }
        .onChange(of: draftState.draft) {
            saveError = nil
            scheduleAutosave()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            flushAutosave()
        }
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

    private var scriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorToolbar
            ScriptTextEditor(
                text: $draftState.draft.scriptContent,
                language: shebangValidation.shebang?.language,
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

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            generateButton
            undoRedoButtons
            Spacer()
            logsButton
            editorExecutionControl
        }
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

    private var generateButton: some View {
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
        .disabled(!isAIAvailable || !shebangValidation.isValid || isGenerating || isRunning)
        .controlSize(.small)
        .help(aiUnavailableReason ?? "Generate script from comments using Apple Intelligence")
    }

    private var logsButton: some View {
        Button {
            onShowLog()
        } label: {
            Label("Logs", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(!hasLogs)
        .controlSize(.small)
        .help("Review the \(ScriptLogStore.recentLogLimit) most recent script executions")
    }

    /// Invalid shebangs replace Run in the same stable control slot.
    @ViewBuilder
    private var editorExecutionControl: some View {
        if shebangValidation.isValid {
            // Dispatches the stored shortcut through the normal trigger path.
            Button {
                run()
            } label: {
                ZStack {
                    Label("Run Script", systemImage: "play.fill")
                        .opacity(isRunning ? 0 : 1)
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isRunning ? 1 : 0)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 16)
            }
            .disabled(!isValid || saveError != nil || isRunning)
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Run this script (⌘↩)")
        } else {
            let presets = ScriptShebangPreset.available

            Menu {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            applyShebang(preset)
                        } label: {
                            Text(preset.line)
                        }
                        .badge(preset.label)
                        .accessibilityLabel("\(preset.line), \(preset.label)")
                    }
                } header: {
                    Text("Choose a shebang for this script.")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    shebangRepairLabel
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 16)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .help(shebangRepairHelp)
            .accessibilityLabel(shebangRepairLabel)
            .accessibilityHint(shebangValidation.message)
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
        do {
            let persisted = try onSave(updated)
            draftState.load(persisted)
            saveError = nil
            showSavedStatus()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func run() {
        flushAutosave()
        guard !draftState.hasUnsavedChanges, saveError == nil else { return }
        onRun()
    }

    private func receiveStoreUpdate(_ shortcut: Shortcut) {
        if draftState.loadedShortcutID != shortcut.id {
            flushAutosave()
        } else if !draftState.hasPersistedEditorChange(in: shortcut) {
            draftState.updateLoadedMetadata(shortcut)
            return
        }

        cancelGeneration()
        generationError = nil
        saveError = nil
        autosaveTask?.cancel()
        savedStatusTask?.cancel()
        savedStatusOpacity = 0
        draftState.load(shortcut)
        editorController.reset()
    }

    private func showSavedStatus() {
        savedStatusTask?.cancel()
        savedStatusOpacity = 1
        savedStatusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                savedStatusOpacity = 0
            }
        }
    }

    private func applyShebang(_ preset: ScriptShebangPreset) {
        let replacement = ScriptShebang.replacingShebang(
            in: draftState.draft.scriptContent,
            with: preset.line
        )
        editorController.replaceAll(with: replacement, actionName: "Set Shebang")
    }

    // MARK: - AI Generation

    private func handleGenerate() {
        generationError = nil
        generateWithModel()
    }

    /// Calls the on-device Foundation Model to generate script code from the user's comments.
    private func generateWithModel() {
        generationTask?.cancel()

        guard let shebang = shebangValidation.shebang else { return }
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
                        right after each relevant comment block. Use \(shebang.interpreterName) \
                        syntax. Output must be valid, runnable shell code.
                        """
                )

                let prompt = """
                    Based on the following commented instructions, generate a complete \
                    \(shebang.interpreterName) script:

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
