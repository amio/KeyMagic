# Application Shortcut Launch Behavior

## Foundations

- Problem: application shortcuts are modeled and labeled as launchers, but the executor manually toggled `hide` / `unhide` state on the first running process that matched a bundle identifier.
- Goal: make application shortcuts fire reliably regardless of the target app's current focus or helper-process topology while preserving the expected hide-on-second-press behavior for the active app.
- Non-goals: changing shortcut storage or altering script and utility shortcut behavior.

## Functional Spec

- Pressing an application shortcut should hide the target app when its activatable instance is already the frontmost app.
- Otherwise the shortcut should launch the target app if no activatable instance is running.
- If the app is already running in the background, the shortcut should unhide and focus the user-facing instance instead of touching helper processes.
- If only background helper processes are currently running for the bundle identifier, TapTick should fall back to Launch Services so the real app instance is brought forward.

## Technical Spec

- `ShortcutExecutor` owns the visibility toggle boundary and only hides an app when the matched running instance is both active and activation-capable (`.regular` or `.accessory`).
- Background app recovery still prefers activation-capable `NSRunningApplication` instances (`.regular`, then `.accessory`) before considering the action a cold launch.
- Launch Services remains the fallback and cold-start path, which avoids coupling shortcut reliability to ad-hoc visibility state inferred from arbitrary matching helper processes.
