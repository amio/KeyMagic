# Shebang-Driven Managed Scripts

Status: Implemented and validated on 2026-08-31.

## Context & Goals

TapTick previously stored script text and a separately selected shell in `shortcuts.json`, then invoked that shell with `-c`. The two runtime declarations could disagree, and supporting another interpreter required another TapTick enum case and UI option.

The agreed model makes scripts ordinary executable files and their shebang the only runtime declaration. The feature must also make the managed directory useful outside TapTick: edits to existing files update the app automatically, and new top-level files become managed scripts automatically.

## Requirements & Invariants

- TapTick persists no runtime selection for a normal script. A usable shebang is required to execute it.
- Missing, malformed, and unavailable shebangs remain editable and saveable but cannot run.
- `Run Script` and the labeled shebang repair menu share one control slot with mutually exclusive visibility. Each control uses its intrinsic label width instead of a fixed or minimum width. The blocking repair menu uses a warning-orange prominent style and reads `Add Shebang` when the script's first character is not `#`, otherwise `Fix Shebang`. Choosing a preset inserts or replaces the first line as one undoable edit. The menu has no executable picker.
- Every managed script is a readable top-level file in the variant-specific `Application Support/<TapTick variant>/Scripts/` directory.
- The script name and file name are the same normalized value. Interactive rename conflicts never overwrite another file and produce an inline error.
- External top-level file additions, content edits, and deletions update TapTick automatically.
- Subdirectories, their contents, hidden files, non-regular files, and symlinks are not managed.
- An external rename is a deletion plus an addition. It does not retain the old UUID, hotkey, logs, or menu-bar reference.
- A borderless circular folder button beside the Scripts title opens the managed directory in Finder and reveals a background highlight on hover.
- Hotkey, menu, and Editor Run continue through `ShortcutExecutor`; menu-bar refresh continues to use only `ScriptRunner`.
- Script source remains in the shortcut record only as a sync/export snapshot. The managed file is authoritative for local editing and execution.

## Proposed Solution

### One Owner and One Naming Invariant

`ShortcutStore` owns both shortcut metadata and the Scripts directory. A normal script action is:

```swift
case runScript(script: String)
```

The source is the portable snapshot. There is no separate persisted file identifier: for a managed script, `shortcut.name` is also its top-level file name. The shortcut UUID remains the identity for hotkeys, logs, sync merge, menu-bar references, and tombstones.

This avoids a second file-name mapping table, sidecars, xattrs, or UUID suffixes. The cost is explicit: renaming a file outside TapTick changes identity because there is no reliable identity metadata to follow.

### Directory Reconciliation

One `ScriptDirectoryMonitor` creates an FSEvents stream for the Scripts directory. A focused platform probe showed that a directory `DispatchSource` sees atomic replacement but misses in-place writes to an existing file; FSEvents is therefore required to satisfy external-editor updates without per-file watchers.

Every event schedules the same 350 ms debounced operation in `ShortcutStore`: enumerate only first-level visible regular files and reconcile the full collection.

```text
FSEvents notification
        │
        ▼
350 ms debounce ──▶ top-level directory scan
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
     same filename   new filename   missing filename
     adopt content   create script  delete metadata
     and snapshot    with new UUID   and add tombstone
```

The scan uses normalized case-insensitive name keys so a case-sensitive volume cannot create a collection that later collides on the normal macOS configuration. Invalid UTF-8 files are left untouched and reported; skipped entries never cause an existing shortcut to be deleted accidentally. Imported files receive user-executable permission even if their shebang is invalid.

Internal writes also produce FSEvents notifications. They require no suppression flag: the later scan sees that file and snapshot already agree and becomes a no-op.

### Names, Writes, and Conflicts

Interactive names are trimmed, Unicode-normalized, non-hidden, no more than one filesystem component, free of control characters, and within the filesystem component byte limit. New scripts choose the first available `Untitled Script`, `Untitled Script 2`, and so on.

An editor rename checks both managed metadata and every top-level directory entry before moving. A collision leaves the current metadata and file intact and surfaces `A script named … already exists.` Atomic content writes are followed by executable-permission repair. Case-only renames use a temporary file name because they cannot be expressed as a direct move on a case-insensitive volume.

Non-interactive ingestion must not block or discard data, so legacy migration, import, and cloud materialization choose a readable numeric suffix when necessary.

### Shebang and Execution

`ScriptShebang` is the shared policy boundary for editor state and execution validation. It accepts executable absolute interpreter paths and `/usr/bin/env` forms, including `env -S`, and derives a shell-highlighting hint when the interpreter is sh, bash, zsh, or fish.

`ScriptExecutionEnvironment` supplies the same deterministic `PATH` to preset detection, shebang validation, and child processes. It includes common Homebrew and user-local locations followed by system locations, without sourcing shell startup files.

`ScriptRunner` receives only a managed file URL. It validates UTF-8 and the shebang, sets the file as `Process.executableURL`, sets the working directory to the Scripts directory, and captures output exactly as before. It never converts the file back into `interpreter -c`.

The preset menu always contains zsh, bash, and POSIX sh, plus detected fish, Python 3, Node.js, and Ruby. AppleScript and JXA presets and dedicated editing affordances remain deferred; manually written valid `osascript` shebangs still pass the generic validator.

### Persistence, Migration, Import, and Sync

`ShortcutSyncState` is versioned. Schema version 2 means managed files have already been established.

On the one-time migration from version 1:

- an old inline script keeps an existing shebang; otherwise its previously selected shell path is prepended as the shebang;
- a readable old external script is copied into Scripts, never moved or deleted, and receives the old shell shebang only when missing;
- an unavailable old external path remains a decode-only legacy action instead of becoming empty content;
- collisions receive deterministic readable suffixes;
- after materialization, a normal directory reconcile imports any unrelated top-level files already present.

On later launches, a missing managed file is treated as an external deletion rather than recreated from the snapshot. This distinction is why the schema version is required.

Export first reconciles disk into snapshots. Import and winning cloud records materialize their snapshots into files. Existing tombstone and newest-`modifiedAt` merge semantics remain unchanged. Older app versions cannot interpret the new no-shell action, so the data change is not backward compatible; release iCloud entitlements remain disabled and no sync rollout is implied by this feature.

### Editor and Folder UI

The shell picker is removed. The editor derives highlighting and AI language context from the shebang. AI generation is unavailable until the shebang validates. The editor control row omits a redundant `Script` caption, starts with Generate and Undo/Redo, and ends with Logs followed by the trailing execution slot. That slot shows an orange prominent shebang repair menu while invalid, then changes in place to the `Run Script` button after repair. The repair label is `Add Shebang` when the script's first character is not `#`, otherwise `Fix Shebang`. Both states size themselves from their intrinsic content without a fixed or minimum width. The menu begins with a noninteractive instruction and presents each preset with its shebang as the item title and its runtime name as the native SwiftUI menu badge, which macOS aligns and styles at the trailing edge. Its accessibility label/help message describes the current failure, and repair is one whole-document Undo operation.

The editor flushes autosave when TapTick resigns active, which covers the normal handoff to an external editor. When the watched file changes, the store-published shortcut replaces the selected draft automatically. Disk is canonical if simultaneous unsaved in-app and external edits race; avoiding that rare last-writer ambiguity with a merge/conflict state machine is intentionally outside this concise design.

## Implementation Plan

1. Version the sync envelope and migrate legacy actions into managed files.
2. Centralize name validation, collision handling, atomic writes, executable permissions, and script command resolution in `ShortcutStore`.
3. Add one FSEvents monitor and a debounced, non-recursive directory reconcile.
4. Replace shell invocation with direct managed-file execution and shared shebang/environment validation.
5. Remove the runtime picker; add shebang repair, Run gating, external draft refresh, and the Scripts folder button.
6. Adapt import/export, cloud materialization, hotkey refresh, menu-bar resolution, and focused tests.
7. Remove the superseded generic shortcut editor/detail views so there is only one script editing path.

## Alternatives Considered

### Keep a runtime enum beside the shebang

Rejected because it preserves two possible authorities and makes every interpreter a product feature.

### Use a directory DispatchSource

Rejected after a local probe demonstrated that it misses in-place writes to existing files. It cannot meet the external-editor requirement.

### Watch every script file

Rejected because additions, deletions, atomic replacements, and watcher lifecycle would create more state than the scripts themselves. One FSEvents stream plus a full shallow scan has one recovery path.

### Persist UUID file names or identity sidecars

Rejected because they make the folder less readable or add hidden coordination files. External rename identity preservation is not worth that complexity in this version.

### Recurse into subdirectories

Rejected by product scope. A flat collection makes naming, collision detection, selection, and reconciliation deterministic.

### Remove source snapshots entirely

Rejected because current export and dormant iCloud sync use one portable JSON document. The duplicate bytes are transport state, not a second local authority.

## Trade-offs & Risks

- **Main complexity — persistence and reconciliation:** the store must keep metadata, a canonical file, a transport snapshot, and deletion tombstones coherent. Startup migration and external deletion are the highest-risk paths.
- **Medium complexity — ingestion collisions:** imports or cloud records can carry different UUIDs with the same name and require deterministic lossless suffixing.
- **Medium complexity — editor handoff:** normal app switching is protected by resign-active autosave, but truly simultaneous edits use disk-wins semantics rather than a merge UI.
- **Low-medium complexity — watcher lifecycle:** FSEvents is one small platform boundary; all behavioral decisions remain in a deterministic scan that is directly unit-testable.
- **Low complexity — execution and UI:** direct executable launch and one shebang menu are smaller than the removed shell matrix.
- External rename deliberately loses TapTick identity. Preserving it later would require an explicit durable identity mechanism and should be evaluated as a separate feature.

The implementation affects the action/sync models, `ShortcutStore`, execution services, the script editor, highlighting, and app hotkey wiring. The substantial code is concentrated in `ShortcutStore` and its tests; the watcher, runner change, folder button, and warning menu are small focused boundaries.

## Validation & Rollout

- Test legacy action decoding and version-1 local migration without source loss.
- Test readable file creation, executable permissions, rename collision handling, persistence round trips, import/export, and deletion tombstones.
- Test deterministic reconciliation for external add, edit, delete, invalid UTF-8, and ignored subdirectories.
- Exercise the real FSEvents monitor with an in-place write, not only an atomic replacement.
- Test direct execution, missing files, missing/malformed/unavailable shebangs, `/usr/bin/env`, nonzero exit status, and large output.
- Test shebang insertion/replacement and shell-highlighting derivation.
- Preserve executor logging/trigger tests and menu-bar serial refresh tests using managed file commands.
- Run formatting, strict lint, all unit tests, Debug build, and `make run` before handoff.
