# Script Output Unification

## Foundations

- Problem: hotkey-triggered script runs and the Scripts settings tab used different execution and formatting paths, which made the on-screen subtitle truncate independently and left the `Output` viewer out of sync with the last hotkey run.
- Goal: make every script execution produce one canonical result model so the subtitle HUD and the Scripts `Output` sheet read the same underlying log.
- Non-goals: changing hotkey registration, script storage, or turning the subtitle HUD into an unbounded full-screen log viewer.

## Functional Spec

- Every inline-script run now records one `ScriptExecutionLog` that carries both the raw output and the shared display helpers used by the UI.
- The bottom-of-screen subtitle remains a compact preview, but it now uses the same last log as the Scripts settings `Output` button instead of its own formatting branch.
- The Scripts `Run` button and global hotkey execution both store their result in the same in-memory log store, so the detail viewer always shows the latest full output for that shortcut.

## Technical Spec

- `ShortcutExecutor` now owns the shared script-process execution helper used by both hotkey dispatch and the Scripts test-run flow, eliminating the duplicated `Process` + `Pipe` logic.
- `ScriptExecutionLog` centralizes the detail-text and subtitle-preview rules, including empty-output and exit-code fallbacks, while `ScriptOutputPresenter` only renders the preview it receives from that model.
