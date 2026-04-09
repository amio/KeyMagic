# Built-In Features and Keystroke Overlay

## Foundations

### Problem

TapTick currently has two shortcut surfaces:

- user-defined application launchers
- user-defined scripts

That model breaks down for system-native utilities that need dedicated permissions, windowing, or internal runtime state. A keystroke subtitle overlay cannot be represented as a plain script because it must keep a long-lived global event listener, manage permission state, and render an always-on-top overlay window.

### Goals

- Add a first-class Built-In Features tab that can host multiple native utilities over time.
- Keep user-defined shortcuts isolated from built-in feature configuration and lifecycle.
- Let built-in features own their own settings, reserved hotkeys, and permission flows.
- Ship the first built-in feature now: a global keystroke subtitle overlay toggled by `cmd + ctrl + opt + k`.

### Non-Goals

- Implement screenshot, window management, or Large Type in this task.
- Build a generic plugin/runtime loading framework.
- Persist built-in features in the user shortcut JSON schema.

## Functional Spec

### Settings Information Architecture

- Add a new top-level `Built-Ins` tab beside General, Applications, and Scripts.
- Inside `Built-Ins`, use a two-pane layout:
  - left: a feature directory that lists available and planned built-ins
  - right: a feature-specific settings panel
- Planned features should still appear in the directory as placeholders so the new IA already scales beyond the first implementation.

### Feature Directory

- Show at least these entries:
  - Keystroke Overlay
  - Screenshot Tools
  - Window Manager
  - Large Type
- Only Keystroke Overlay is active in this task.
- Planned entries should expose intent and status without presenting dead controls.

### Keystroke Overlay Behavior

- Reserved default hotkey: `cmd + ctrl + opt + k`.
- Pressing the hotkey toggles the overlay listener on and off.
- When enabled, the feature listens to global keyboard input and shows the latest chord as an on-screen subtitle near the lower center of the active screen.
- Supported settings:
  - enabled state
  - hotkey override
  - font size
  - foreground color
  - background color
  - visible hold duration
  - fade-out duration
- If input-listening permission is missing, the settings panel must communicate that clearly and offer a request flow.

## Technical Spec

### Ownership

- `ShortcutStore` remains the authority for user-authored shortcuts only.
- A new built-in feature controller owns:
  - built-in feature metadata
  - persisted built-in settings
  - built-in reserved hotkeys
  - permission-aware runtime services

This keeps long-lived native features out of the generic shortcut schema and avoids turning `ShortcutStore` into a mixed-purpose registry.

### Hotkey Routing

- Extend `HotkeyService` so it can register both:
  - the reserved settings-window hotkey
  - reserved built-in feature hotkeys
  - user-defined shortcuts
- Conflict detection must include built-in reserved hotkeys so feature toggles cannot collide with scripts or app launchers.

### Input Permission Strategy

- Use `CGEventTap` in listen-only mode instead of `NSEvent.addGlobalMonitorForEvents`.
- Rationale:
  - Apple’s AppKit header states global key monitors require Accessibility trust for key-related events.
  - CoreGraphics exposes `CGPreflightListenEventAccess` and `CGRequestListenEventAccess`, which map directly to input-event listening access and fit this feature better.
- Permission state must be modeled explicitly so the UI can distinguish:
  - ready
  - missing access
  - actively capturing

### Overlay Runtime

- Keep overlay capture and overlay presentation separate:
  - capture service: owns the event tap, permission checks, and key event normalization
  - overlay presenter: owns a borderless floating panel and fade timing
- The presenter should be reusable by future built-ins that may need temporary on-screen HUDs.

### Persistence

- Persist built-in settings independently from `shortcuts.json`.
- Store the built-in configuration as JSON in the existing app support directory so it can evolve without changing the shortcut schema.

### Key Rendering

- Reuse existing key name mappings where possible so the overlay and hotkey recorder present a consistent visual language.
- The overlay should render modifier-only changes and normal key chords as one composed display string.
