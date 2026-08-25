# Menu Bar Text Cleanup

## Context & Goals

The feature now satisfies its product goal, but iterative UI tuning left runtime, rendering, preview interaction, and editor concerns more coupled than necessary. This cleanup preserves the accepted behavior exactly while reducing parallel state, duplicated mutation logic, and mixed file responsibilities.

## Requirements & Invariants

- Zero or more ordered slots appear immediately after TapTick's icon inside the same native menu button; an unbound slot is visible only in Settings.
- A slot persists a 24–240 pt width (50 pt default), single/two-line layout, centered-by-default left/center/right alignment, and retained top/bottom line configurations.
- Every active line independently selects an existing script and refreshes immediately, then serially every 1–3600 seconds (3 seconds by default). Slow runs never overlap on the same line.
- Initial binding and reactivation show `…` until the first result. Script or interval changes wake the line immediately but retain the previous visible content until the replacement result arrives; an in-flight obsolete result is discarded. Presentation-only width, alignment, and ordering changes do not wake the line.
- Switching from two lines to one clears the bottom line's display state without deleting its configuration. Switching back shows `…` and runs it immediately. A single worker survives that inactive period so rapid toggles cannot overlap processes.
- Script source is resolved from `ShortcutStore` on every run. Background refresh never writes explicit execution logs or presents the subtitle HUD.
- Output whitespace is normalized; empty success, missing script, and failure fallbacks remain unchanged.
- Existing single-script and earlier per-line configuration files remain readable, with missing width/alignment migrated to 50 pt/center.
- Settings preserves the accepted preview geometry, typography, selection, ordering, deletion, accessibility, and stable global-coordinate resize behavior. Width is previewed without animation and persisted only when dragging ends.

## Proposed Solution

- Keep `MenuBarTextSlot` as the persisted source of truth, but give the model one normalization boundary for width and both refresh intervals. The controller applies it before comparing or persisting a mutation.
- Keep `MenuBarTextController` as the sole runtime owner. Replace parallel task/definition dictionaries with one refresh-job registry whose entry owns a persistent serial worker, its optional current definition, and its interruptible delay. Definition changes wake the same worker; they never start a competing process.
- Inject only the context-free `ScriptRunner`. This keeps process execution shared while making execution order and overlap deterministic in controller tests without inventing a general scheduler or clock abstraction. Stage completed content behind one controller-owned publication interval so production and preview refresh from the same snapshot.
- Expose a single slot mutation operation and let Settings bindings address a slot by ID instead of copying and updating whole slots in four independent helpers.
- Keep `MenuBarStatusContentView` production-only: fixed status-item geometry, icon/text drawing, typography, and width calculation. Cache its two fonts and remove preview-only geometry from it.
- Move Settings-only menu-bar height, selection decoration, AppKit bridging, and resize interaction into a dedicated preview component. Keep the accepted layering that puts decoration behind the shared renderer and hit targets above it.
- Keep `MenuBarTextSettingsView` responsible only for selection, slot lifecycle, and composition of the preview/editor. Localize editor controls in a focused component so visual details do not expand the orchestration surface.
- Keep `MenuBarController` as the only `NSStatusItem`/`NSMenu` owner. Preserve separate observation paths because shortcut mutations rebuild the menu, while frequent text refreshes must update only the status content. Capture observed dependencies rather than the owner across suspension so its task properties do not form a lifecycle cycle.

## Independent Review Outcome

- The review confirmed that the renderer/preview split, explicit top/bottom storage, and separate menu/text observation paths match their distinct responsibilities and should remain.
- It identified process overlap as the material flaw in the earlier restart-on-change task model because cancelling the Swift task cannot terminate a script already blocked in `Process.waitUntilExit()`. Persistent per-line workers now serialize those transitions, discard obsolete results, and only suspend while their definition still matches the one just processed so a configuration wake-up cannot be lost.
- It also moved migration coverage through the real controller file boundary and introduced a narrow async runner seam for deterministic lifecycle tests without adding a general scheduler abstraction.

## Implementation Plan

1. Centralize model normalization and controller mutation; replace restart-on-change tasks with one persistent serial worker per configured line.
2. Extract the preview and editor components without changing layout values or gesture semantics.
3. Narrow the shared renderer to production rendering and cache derived fonts.
4. Remove superseded helpers, parallel dictionaries, stale comments, and observation-owner cycles.
5. Update architecture documentation and add boundary-level coverage for normalized mutations, serial definition changes, and controller-level legacy file loading.

## Trade-offs & Risks

- Keeping both legacy decoders costs code but protects real local configuration created during earlier iterations.
- Explicit top/bottom storage is slightly more verbose than an array, but it preserves hidden bottom-line configuration across layout toggles without introducing array-cardinality repair logic.
- The preview retains separate background and interaction layers. Collapsing them would save a small amount of view code but risks changing renderer z-order and the already-fixed drag hit testing.

## Validation & Rollout

- Preserve and extend persistence, migration, clamping, output-normalization, and ordering tests.
- Add scheduler boundary tests proving two configured lines execute immediately and that execution-time definition/toggle changes remain serial.
- Write both legacy schemas into the real `menu-bar-text.json` envelope and load them through `MenuBarTextController`.
- Run `make format`, strict lint, all unit tests, and a Debug build.
- Leave final visual and interaction verification to the user, as requested.
