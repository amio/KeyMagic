# Settings Window Lifecycle

## Foundations

- Problem: Settings activation and dismissal differed across the global hotkey, menu-bar item,
  Dock reopen, and native close paths. Escape could leave TapTick active with no visible window or
  restore a stale application, while Dock visibility was changed directly by a Settings view.
- Goal: make TapTick behave as a resident menu-bar utility whose Settings window has one lifecycle,
  returns focus after dismissal, and keeps Dock visibility independent from window visibility.
- Non-goal: change the lifecycle of screenshot, update, or nonactivating script-output windows.
- Requirements: login-item launches stay quiet; manual and first launches show Settings; closing the
  last interactive TapTick window does not terminate the app; existing Dock preferences remain
  respected, with new installations defaulting to a menu-bar-only presentation.

## Functional Spec

- The global hotkey brings a hidden or background Settings window forward and dismisses it only when
  it is already key.
- Escape hides the reusable Settings window, keeps TapTick running, and returns focus to the latest
  external foreground app. Native close paths perform the same focus handoff.
- Activating TapTick through the Dock, Finder, or app switcher shows Settings when no TapTick
  interactive window is visible. Login-item launch creates no window and takes no focus.
- The Dock icon follows only `showDockIcon`. Changing it does not dismiss Settings, and dismissing
  Settings does not change it.
- New installations start without a Dock icon; users who already selected a Dock preference retain it.

## Technical Spec

- `AppDelegate` is the sole app-presentation owner. It registers the SwiftUI-created Settings window,
  observes native close events, tracks the most recent non-TapTick activation through `NSWorkspace`,
  and applies activation policy from `UserDefaults`.
- Opening records a presentation request independently from SwiftUI scene creation. Once the
  `NSWindow` resolves, the app requests activation and makes that window key; the request remains
  pending until AppKit confirms key-window status. Reopening always requests activation so it also
  cancels an unfinished cooperative yield from a preceding dismissal.
- Settings uses one persistent unified window toolbar and a native `NavigationSplitView`. AppKit owns
  the standard controls, titlebar geometry, hover tracking, active-window appearance, and button
  actions; application code never repositions those controls. The functional system sidebar toggle
  remains the root toolbar item so every page preserves the same toolbar geometry, while the window
  owns one explicit titlebar separator style rather than deriving it from page scrolling content.
- Dismissal uses cooperative activation by yielding to the remembered `NSRunningApplication` before
  activating it; if no valid target exists, hiding TapTick lets macOS select the next active app.
  Focus is retained when another interactive TapTick window is visible.
- `keyAELaunchedAsLogInItem` in the launch Apple Event is the authoritative quiet-launch signal;
  parent-process names are not used because LaunchServices can route manual UIElement launches through
  `launchd` too.
- `LSUIElement` establishes the default accessory identity before launch completes. Runtime activation
  policy restores `.regular` for existing users whose stored preference enables the Dock icon.

## Validation

- Strict formatting and linting.
- Full unit suite and Debug build.
- UI coverage for manual Settings launch, navigation, Escape dismissal, process survival, focus
  handoff to the background state, and Settings restoration when the windowless app is activated.
