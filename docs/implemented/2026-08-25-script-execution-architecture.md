# Script Execution Architecture

Status: Implemented on 2026-08-25.

## Context & Goals

TapTick executes scripts through explicit shortcut triggers, the Scripts editor, menu items, and periodic menu-bar text refreshes. The process boundary is shared today, but explicit execution policy is split across `HotkeyService`, `ShortcutExecutor`, `AppDelegate`, and `ScriptsView`, while menu-bar workers publish each line independently.

The goal is to give script process execution, explicit-run side effects, background scheduling, logs, errors, and UI publication clear owners with the smallest complete set of boundaries. Menu-bar text and its Settings preview should publish completed results together on a shared approximate one-second cadence; strict wall-clock synchronization is not required.

## Requirements & Invariants

- Hotkey, menu-item, and Editor Run executions keep the same explicit-run behavior: resolve the latest stored shortcut, update its local trigger timestamp, persist a log, and present the subtitle when applicable.
- Periodic menu-bar refreshes reuse the same low-level process mechanism but never update explicit logs, trigger metadata, or subtitles.
- The stored shortcut remains the runtime source of truth.
- Each menu-bar line remains serial. Configuration changes cannot overlap a replacement process with an obsolete non-cancellable process, and obsolete results are discarded.
- Real menu-bar content and Settings preview derive from one published content snapshot.
- Each script retains its own 32 most recent explicit execution logs. Existing flat `script-logs.json` records remain readable.
- Existing menu-bar configuration schemas remain readable.

## Proposed Solution

### Process Boundary

Introduce a stateless `ScriptRunner` that accepts only `ScriptCommand` values and returns one canonical `ScriptExecutionResult`. The result owns start time, duration, combined captured output, and typed termination state. The live runner drains the output pipe while the child is running, then awaits process completion.

### Explicit Execution

Promote `ShortcutExecutor` to a process-lifetime `@MainActor` service created by `AppState`. It resolves shortcut IDs through `ShortcutStore`, owns app-launch behavior, starts script runs through `ScriptRunner`, records completed logs, presents subtitles, and exposes active run IDs.

`HotkeyService` owns only registration and dispatches a shortcut ID through one callback. Menu items and the Scripts editor call `ShortcutExecutor` directly. Editor progress follows the run ID returned by the executor instead of inferring completion from log mutations.

### Background Menu-Bar Execution

Keep `MenuBarTextController` as the configuration, scheduling, and display owner. Its persistent per-line workers continue to serialize process executions through `ScriptRunner`. Completed results are staged in a pending map. One controller-owned approximate one-second publication task validates and applies all pending results through a single `contentByLineKey` assignment, which gives the real menu bar and preview the same published revision without coupling independent script lifetimes.

### Logs

`ScriptExecutionLog` composes the canonical result while preserving the existing flat Codable representation. `ScriptLogStore` keeps one ordered history array, trims it independently to 32 entries per shortcut, and derives filtered history directly from that array.

## Implementation Plan

1. Add `ScriptRunner`, `ScriptCommand`, and the canonical result/termination model.
2. Rework `ShortcutExecutor` into the shared explicit execution owner and rewire app composition, hotkeys, menu items, and Editor Run.
3. Fold duplicated log state and replace Editor log-ID completion inference with returned run IDs.
4. Stage menu-bar results and publish them on one shared approximate one-second cadence.
5. Update tests and project architecture guidance, then run formatting, lint, unit tests, Debug build, and the app.

## Alternatives Considered

- A universal executor with logging, subtitle, and trigger booleans was rejected because it would turn supported contexts into an expanding policy option matrix.
- Awaiting every due menu-bar script before publishing was rejected because one slow or hung script would stall unrelated lines.
- Cancelling and replacing per-line workers was rejected because cancelling the Swift task does not guarantee the underlying process has stopped.
- A general clock or scheduler abstraction was rejected; a feature-local publication interval is sufficient.

## Trade-offs & Risks

- Batched menu-bar publication can add up to roughly one second of display latency.
- Explicit runs remain independently concurrent. Active run IDs make this state visible without imposing a new global serialization policy.
- Timeout, forced cancellation, output-size limits, and separate stdout/stderr capture remain outside scope. The new process boundary is the single future owner for those policies.
- Changing the in-memory log composition requires custom flat encoding and decoding to avoid migrating or dropping existing history.

## Validation & Rollout

- Test successful, failed, missing-file, and high-output process execution at the runner boundary.
- Test that explicit execution updates trigger metadata, records one log, and owns active run state.
- Preserve application-launch tests under the process-lifetime executor.
- Test per-script 32-entry trimming and persisted-history compatibility.
- Preserve menu-bar per-line serialization tests and add coverage for delayed shared publication and obsolete pending-result rejection.
- Run `make format`, `make lint`, `make test`, and `make run`.
