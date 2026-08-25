# Script Editor Autosave and Undo/Redo

## Foundations

### Problem

The Scripts editor originally required an explicit Save action. Autosave removed that interruption, but recovery was first implemented as persisted snapshots with custom back/forward navigation. That model conflicted with normal editor expectations: navigating mutated persistence, redo paths were fragile, and the code duplicated behavior already owned by the macOS text system.

### Goals

- Save valid editor changes after two seconds of inactivity, before Run, or when leaving the editor.
- Provide standard text Undo/Redo through both buttons and the native Command-Z / Shift-Command-Z shortcuts.
- Provide the native Find bar and incremental search through standard macOS commands.
- Give each script editor session its own undo stack so other Settings fields do not affect script undo.

### Non-goals

- Persisting undo history across app launches or script selections.
- Implementing a parallel version-history schema.
- Adding custom undo behavior for the name field or shell picker.

### Requirements

- The stored shortcut remains the sole runtime source of truth for script execution.
- Autosave updates only editor-owned fields and cannot overwrite a concurrent hotkey change.
- Undo and Redo use the same native stack whether invoked by button or keyboard.
- Programmatic state loading must not create undo entries.
- Editor-originated replacements such as templates and generated scripts must create one native undo entry.
- Undo/Redo text changes follow the same autosave rules as typing.

## Functional Spec

- The editor displays Saved, Unsaved changes, or Name required status.
- Typing resets a two-second idle timer. Run and editor disappearance flush valid pending changes immediately.
- Undo and Redo buttons appear beside the Script label and use the standard macOS arrow symbols.
- Command-Z and Shift-Command-Z invoke the same actions through the AppKit responder chain.
- Command-F presents the native incremental Find bar.
- Natural-language correction, completion, substitution, and Writing Tools remain disabled for shell code.
- The native UndoManager uses its default history-depth behavior.

## Technical Spec

### Ownership

`ScriptEditView` owns draft and autosave state. `ScriptTextEditor` owns the AppKit text boundary, and `ScriptTextEditorController` owns editor commands, the per-editor `UndoManager`, and observable button state. The app scene installs SwiftUI's standard `TextEditingCommands` so Find menu shortcuts reach the current AppKit first responder. `ShortcutStore.updateScript` persists only name and action while preserving the latest unrelated shortcut fields.

### Editor Boundary

`ScriptTextEditor` wraps a plain-text `NSTextView`. The text view enables native undo and Find, receives its dedicated manager through `NSTextViewDelegate.undoManager(for:)`, and disables natural-language transformations that can corrupt shell code. Buttons call the manager directly, while standard keyboard commands reach the same manager through AppKit. The coordinator observes completed Undo/Redo operations to synchronize their text back to the SwiftUI draft because `UndoManager` changes the text storage without sending `textDidChange(_:)`. External binding updates temporarily disable undo registration so initial loads and model refreshes do not pollute the stack. Editor commands instead replace text through `NSTextView`, making each generated result or template one native undoable edit.

### Save Flow

1. User typing, Undo, or Redo updates the SwiftUI binding through the text-view delegate.
2. The binding change marks the draft dirty and starts or resets the two-second timer.
3. The timer, Run, or editor disappearance sends editor-owned fields to `ShortcutStore.updateScript`.
4. The store merges those fields into its latest shortcut value, then uses the existing local and cloud persistence path.

### Validation and Rollout

- Unit-test that script-specific persistence preserves unrelated current fields.
- Verify strict formatting/lint, unit tests, Debug build, and application launch.
- The superseded `script-revisions.json` is no longer read or written. Any development-era file is harmless and ignored.

### Trade-offs and Risks

- Undo history is session-local, matching normal editor behavior; it does not survive selecting another script or relaunching the app.
- A focused AppKit bridge adds a small platform boundary, but it gives the script editor one authoritative native undo stack instead of maintaining parallel persistence and navigation state.
