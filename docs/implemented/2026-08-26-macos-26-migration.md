# macOS 26 Migration (Implemented)

## Context & Goals

TapTick currently targets macOS 15 while being developed with Xcode 27 and Swift 6.4. Most process-lifetime services already use Observation and explicit `@MainActor` ownership, and the app already offers an on-device Foundation Models script generator behind a macOS 26 availability branch. The remaining compatibility surface keeps the Settings window fixed-size, retains one Combine-era root state object, uses synchronous AppKit file panels from SwiftUI, and implements several custom pointer-only controls and a pre-Tahoe screenshot toolbar.

The goal is to make macOS 26 the actual minimum supported release, adopt the platform APIs and interaction conventions that improve the existing product, and preserve every current TapTick capability. UI layout and styling may change where the macOS 26 design system provides a clearer native equivalent.

## Requirements & Invariants

- The Xcode application, Swift package, built bundle, documentation, and download site must consistently declare macOS 26 as the minimum release.
- Application launchers, shell scripts, global hotkeys, native utilities, menu-bar text, script logs, import/export, update checks, and the screenshot annotation workflow must remain available.
- Existing shortcut, utility, menu-bar, script-log, and cloud-sync data must remain readable without a migration or schema change.
- The Debug/Release identities, Application Support separation, Carbon registration namespace, process-lifetime executor, menu-bar worker semantics, and disabled distribution entitlements must remain unchanged.
- Apple Intelligence availability must still be determined at runtime because hardware eligibility, model readiness, and the user setting are independent of the deployment target.
- macOS 27-only behavior must remain availability-gated because macOS 26 remains supported.
- Liquid Glass must remain a functional controls/navigation layer. Content surfaces such as forms, script output, overlays, and the screenshot itself must not become decorative glass cards.

## Proposed Solution

### Platform and release boundary

Set both XcodeGen deployment declarations and the Swift package platform to macOS 26. Regenerate the Xcode project from `project.yml`, and update README and public download requirements. Keep the current Swift 6 strict-concurrency and Xcode 27 project settings.

### Runtime ownership and concurrency

Migrate the composition-root `AppState` from `ObservableObject`/`@Published`/`@StateObject` to Observation/`@State`. Mark non-observed AppKit references as ignored by Observation. Isolate `LoginItemManager` to `@MainActor`, remove redundant `@unchecked Sendable` declarations from global-actor-owned services/controllers, and replace main-queue deferrals with cancellable `Task`-based deferrals. The genuinely cross-thread observer bag and Foundation formatter keep their explicit unchecked conformances.

### Settings scene and navigation

Keep the singleton SwiftUI `Window` scene and its AppDelegate-owned presentation lifecycle. The app is an `LSUIElement` utility whose menu, global hotkey, manual launch, Dock policy, and close-time focus handoff all converge on this owner; replacing it with a `Settings` scene would remove the always-live `openWindow` trigger and reopen recently solved activation behavior.

Make the Settings window resizable with a minimum content size and a larger declared default size. Let `NavigationSplitView` own the Tahoe sidebar appearance, use standard `Label` rows and a flexible sidebar width, expose `SidebarCommands`, and stop forcing a toolbar background. Scripts and Utilities use native `List(selection:)` semantics instead of pointer-only row tap gestures. Application enablement remains an explicit switch rather than an invisible whole-row action.

### SwiftUI-native file workflows

Replace synchronous `NSOpenPanel`/`NSSavePanel.runModal()` calls in SwiftUI views with `fileImporter`/`fileExporter`. Keep the existing store serialization as the sole shortcut file format owner, add user-visible error reporting, and handle security-scoped URLs at the UI boundary. App and script-file pickers likewise use `fileImporter` while preserving the selected bundle ID or file path.

### Foundation Models

Remove unreachable macOS 26 availability branches and call `FoundationModels` directly. Continue checking `SystemLanguageModel.default.availability`, retain all hardware/settings failure messages, and own generation with a cancellable task so a closed or replaced editor cannot publish stale output. Use the standard system help UI instead of the custom hover-only tooltip.

### Tahoe screenshot controls

Keep the AppKit `NSPanel` and custom `NSView` canvas because SwiftUI has no equivalent for the current pixel-precise drawing and responder-chain behavior. Remove the manually imposed window corner/traffic-light offsets and let AppKit own window chrome. Use the macOS 26 `NSView.LayoutRegion` guide to keep the hosted toolbar clear of rounded corners. Replace custom tap targets with accessible SwiftUI `Button`/segmented `Picker` controls, group the custom toolbar actions with `GlassEffectContainer`, and apply native glass button styles only to those interactive actions. Replace the option-hold `DispatchWorkItem` with a cancellable clock-based task.

## Implementation Plan

1. Update deployment metadata and public compatibility text, then regenerate the project.
2. Migrate root Observation and global-actor ownership; remove only redundant unchecked conformances.
3. Modernize Settings window sizing, sidebar navigation, selectable sublists, and file workflows.
4. Simplify Foundation Models availability/task handling and remove the custom tooltip path.
5. Rebuild the screenshot titlebar controls on the macOS 26 glass/layout APIs while preserving canvas and keyboard behavior.
6. Format, lint, run unit tests, build Debug and Release, inspect the built bundle's minimum OS metadata, then launch the Debug app for manual user verification.

## Alternatives Considered

### Replace the app shell with `Settings` and `MenuBarExtra`

Rejected because these are not equivalent owners for TapTick. The Settings window has explicit UIElement activation and focus-handoff requirements, while the menu-bar item renders variable-width one- or two-line script output and owns a native `NSMenu`. Replacing either boundary would add lifecycle coordination and risk functional regressions without improving the requested macOS 26 adoption.

### Apply Liquid Glass throughout Settings content

Rejected because Apple defines Liquid Glass as a sparse functional layer for navigation and controls, not a content material. Standard `Form`, `List`, and editor backgrounds already receive the correct Tahoe appearance when rebuilt with the current SDK.

### Add unrelated macOS 26 capabilities

Spotlight actions, widgets, Continuity, and additional AI features do not modernize an existing TapTick capability. They would broaden product scope and entitlement/runtime ownership, so they are excluded.

## Trade-offs & Risks

- Users on macOS 15 through 25 can no longer install or update to this build. Existing local data is untouched, but downgrading the app binary is the only rollback for those systems.
- Resizable Settings content can expose layout assumptions that a fixed 980×600 window hid. A conservative minimum size and native scroll/list containers limit this risk.
- Native file importers do not guarantee the old panels' initial directory, but they provide system-standard, nonblocking presentation and security-scoped access.
- The screenshot toolbar's visual geometry changes because system window corners and glass controls replace hand-tuned offsets. Keyboard shortcuts and annotation semantics remain the validation authority.
- Removing redundant unchecked conformances may reveal previously masked isolation mistakes at compile time; those errors must be fixed at the owning actor rather than by restoring unsafe annotations.

## Validation & Rollout

- Run `make gen` after `project.yml` changes and verify the generated project contains macOS 26 targets.
- Run `make format` and strict `make lint`.
- Run the full unit-test target, with particular attention to shortcut persistence/sync, hotkey conflicts, utilities, script execution/logging, and menu-bar scheduling.
- Build both Debug and Release with Swift 6 strict concurrency and no new warnings.
- Inspect the built app's `LSMinimumSystemVersion` and Mach-O `LC_BUILD_VERSION` to confirm 26.0.
- Do not automate TapTick's UI. Launch the validated Debug app with `make run` so the user can manually check resizing, Sidebar commands, file pickers, AI availability messaging, and the screenshot annotation toolbar.

There are no schema changes, data migrations, legacy-data rewrites, or entitlement changes. Rollback is therefore binary-only: an earlier TapTick build continues to read the same persisted data.
