# Keystroke Overlay Preview Lifecycle

## Foundations

### Problem

The keystroke overlay currently treats every configuration write as a runtime re-apply. When the feature is disabled or missing permission, that re-apply path stops capture and immediately hides the HUD, so the settings panel's live preview flashes even though the user is still in the middle of a tuning session.

### Goals

- Separate real keystroke presentation from settings preview presentation.
- Let preview remain visible across repeated position and timing edits without hide/show churn.
- Reuse the configured visible time as the keep-alive window for preview edits.

### Non-Goals

- Introduce a second HUD component or a second overlay window.
- Change the persisted settings schema.

## Functional Spec

- Real keystroke capture still renders transient event-driven HUD updates.
- Live preview becomes a first-class presentation scene with its own ownership rules.
- While preview is active, changing position, visible time, fade-out, font size, or colors updates the currently visible HUD in place.
- While preview is active, event-driven HUD updates must not steal the panel, because slider nudges and other settings interactions are part of the preview workflow.
- Stopping capture because the feature is disabled or permission is unavailable should only dismiss an event-driven HUD, not an active preview HUD.

## Technical Spec

- Keep one presenter and one panel, but explicitly track the active presentation intent: `event` or `preview`.
- Capture lifecycle changes only own event presentation shutdown. Preview lifecycle owns preview dismissal and keep-alive timing.
- Preview remains visible by renewing the same session on every relevant settings mutation; the presenter cancels the previous dismissal task, restores full opacity, reapplies layout, and schedules the next dismissal from the latest mutation time.
- Event presentation is suppressed while preview intent is active so live tuning cannot be interrupted by captured keystrokes from the settings workflow itself.
