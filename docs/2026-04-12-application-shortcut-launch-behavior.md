# Application Shortcut Launch Behavior

## Foundations

- Problem: application shortcuts are modeled and labeled as launchers, but the executor manually toggled `hide` / `unhide` state on the first running process that matched a bundle identifier.
- Goal: make application shortcuts fire reliably regardless of the target app's current focus or helper-process topology.
- Non-goals: introducing a new per-app toggle mode, changing shortcut storage, or altering script and utility shortcut behavior.

## Functional Spec

- Pressing an application shortcut should always launch the target app if no activatable instance is running.
- If the app is already running, the shortcut should unhide and focus the user-facing instance instead of hiding it.
- If only background helper processes are currently running for the bundle identifier, TapTick should fall back to Launch Services so the real app instance is brought forward.

## Technical Spec

- `ShortcutExecutor` owns the launch-or-focus boundary and prefers activation-capable `NSRunningApplication` instances (`.regular`, then `.accessory`) before considering the action a cold launch.
- Existing running apps are focused with `activate(options: [.activateAllWindows, .activateIgnoringOtherApps])` so activation does not depend on TapTick being frontmost.
- Launch Services remains the fallback and cold-start path, which avoids coupling shortcut reliability to ad-hoc visibility state inferred from arbitrary matching processes.
