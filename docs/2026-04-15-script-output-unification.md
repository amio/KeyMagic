# Script Output Unification

## Foundations

- Problem: hotkey-triggered script runs and the Scripts settings tab used different execution and formatting paths, which made the on-screen subtitle truncate independently and left the `Output` viewer out of sync with the last hotkey run.
- Goal: make every script execution produce one canonical result model so the subtitle HUD and the Scripts `Output` sheet read the same underlying log.
- Non-goals: changing hotkey registration, script storage, or turning the subtitle HUD into an unbounded full-screen log viewer.

## Functional Spec

- Every inline-script run now records one `ScriptExecutionLog` that carries both the raw output and the shared display helpers used by the UI.
- The bottom-of-screen subtitle remains a compact preview, but it now uses the same last log as the Scripts settings `Output` button instead of its own formatting branch.
- The Scripts `Run` button and global hotkey execution both store their result in the same persisted, per-script history, so the detail viewer always shows the latest full output for that shortcut.

## Technical Spec

- `ScriptRunner` owns the shared context-free process boundary, while the process-lifetime `ShortcutExecutor` owns trigger metadata, explicit logs, active-run state, and subtitle presentation for hotkey and Scripts test runs.
- `ScriptExecutionLog` centralizes the detail-text and subtitle-preview rules, including empty-output and exit-code fallbacks, while `ScriptOutputPresenter` only renders the preview it receives from that model.
