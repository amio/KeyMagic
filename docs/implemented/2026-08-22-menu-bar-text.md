# Menu Bar Text

## Foundations

- Problem: TapTick can run scripts on demand, but it cannot surface script-produced status text continuously in the macOS menu bar.
- Goal: let users configure zero or more ordered menu bar text slots, give each slot an explicit width that defaults to 50 points, choose a one-line or two-line layout plus left/center/right alignment, and bind every visible line to an existing Scripts entry with an independent refresh interval that defaults to three seconds.
- Non-goals: duplicating the script editor, adding a separate inline-script format, syncing slot configuration through iCloud, or turning menu bar output into an execution log.

## Functional Spec

- Settings gains a `Menu Bar` tab. Its default state contains no slots and therefore adds no text item to the menu bar.
- The top of the tab is an unlabeled menu-bar preview: TapTick's actual menu bar icon appears first, followed immediately by every slot in order, with a fixed `Add Slot` action at the right. Clicking a preview slot selects it; adding a slot creates and selects a new unbound slot.
- Only the selected slot's editor appears below the preview. Its left-aligned layout and alignment controls are followed by one script row for `Single Line` or two unlabeled script rows for `Two Lines`; every row owns its script picker and whole-second refresh interval, while accessibility still distinguishes top and bottom. Alignment defaults to center and applies to every active row in the slot.
- The preview separates the current screen's full visible menu-bar height from the smaller status-item content thickness: its outer bar, interaction regions, and selected background use the former, while the shared icon/text renderer keeps the latter. The selected background uses a compact rounded rectangle with the same three-point vertical inset as a highlighted menu bar button. Hovering the slot's trailing edge reveals a horizontal-resize handle outside that background; dragging uses a stable global coordinate space, previews integer-point width without animation, and persists the clamped value on release.
- The focused editor and preview bar share the same horizontal bounds, so configuration controls align directly with the surface they modify. The user explicitly selects each script, so adding a slot or second line never runs an arbitrary script automatically.
- Configured slots appear immediately to the right of TapTick's icon inside the same status button. Clicking the icon or any slot opens the existing TapTick menu as one native click target.
- Each script output is trimmed and collapses all whitespace into its configured menu-bar line. Numbers use tabular spacing without changing the proportional system font for other characters, and two-line slots use a tighter baseline step. Long lines truncate visually without changing the underlying output.
- A slot collapses when every active script returns empty successful output and expands again when content returns. Collapse, expansion, and fit-to-content width changes animate together with the status item width; missing scripts and failures without output remain visible as short diagnostics.
- Scheduled runs are serial per configured line: the next interval starts after the current run completes, preventing slow scripts from accumulating overlapping processes while allowing two-line slots to refresh independently. Script, interval, and layout changes wake the same persistent worker; an obsolete in-flight result is discarded before the replacement runs, so rapid reconfiguration never overlaps a line's processes.

## Technical Spec

- `MenuBarTextController` owns slot persistence, refresh tasks, and resolved display values; `MenuBarController` remains the sole owner of the app's `NSStatusItem` and native menu. Configuration is stored in the runtime-variant Application Support directory beside other local settings.
- A slot stores its UUID, layout, alignment, fixed width, and retained top/bottom line configurations; each line configuration contains a referenced script UUID and refresh interval. Script source remains owned by `ShortcutStore`, and each refresh resolves the latest action so script edits and deletions take effect without copied state.
- `MenuBarController` installs one shared AppKit content view inside the standard status bar button. The renderer draws the icon followed by the controller's ordered slots and owns their animated presentation widths, while the surrounding system button owns highlighting, the full hit target, menu presentation, and the matching animated total width.
- Settings embeds that same AppKit renderer through `MenuBarStatusPreview`, which owns screen-height geometry plus accessible selection and trailing-edge resize targets; `MenuBarTextSlotEditor` separately owns the focused controls. Fonts, truncation, widths, icon spacing, and line alignment therefore stay identical without mixing preview behavior into the production renderer.
- Periodic execution calls the context-free `ScriptRunner` boundary directly. It does not publish to `ScriptLogStore` or `ScriptOutputPresenter`, because background refreshes must not overwrite explicit run logs or show a subtitle every few seconds. Completed line results are staged and published together on an approximate one-second cadence so the real menu bar and Settings preview observe the same content revision.
- The decoder migrates prior schemas with centered alignment and a 50-point width; the original one-script schema also moves the existing script and interval into the top line. Switching layouts later retains both line configurations instead of discarding user input.
- Slot mutations pass through one normalized controller boundary. Runtime jobs keep definition, wakeable delay, and worker ownership together instead of coordinating parallel task/definition dictionaries; the injected package-internal runner exists only to test this side-effect boundary deterministically.

## Trade-offs & Risks

- Existing scripts may have side effects. Requiring explicit script selection prevents accidental execution on slot creation, but the user remains responsible for choosing a safe status script.
- Slot configuration is local-only, matching utility settings and avoiding a second conflict-resolution model in the shortcut sync envelope.
- A hung script stalls only its configured line because runs intentionally do not overlap. Process timeout and cancellation are outside this feature's requested scope.
- Slot width is clamped to 24–240 points so unbounded output cannot consume the whole menu bar; truncation remains presentation-only and accessibility keeps the full string.

## Validation & Rollout

- Unit-test default configuration, alignment/width/per-line persistence, ordering, clamping, both legacy file migrations, single-row output normalization, empty-output collapse sizing, immediate two-line execution, and serialization across bottom-line deactivation/reactivation.
- Run the repository formatter, strict lint, unit tests, and Debug build.
- Verify manually that Settings and the real menu bar have identical height and icon/slot geometry, the resize indicator sits outside the selected background, all three alignments match across surfaces, dragging updates smoothly and persists on release, empty output animates its slot closed and later content reopens it, fit-to-content changes animate without jumps, and clicking anywhere in the combined icon/slot button opens the TapTick menu.
