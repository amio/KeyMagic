# Keystroke Overlay Permission Button Recovery

## Foundations

### Problem

The keystroke overlay permission button already dispatches its action, but the current permission owner only calls `CGRequestListenEventAccess()`. Once macOS has already denied or exhausted the one-shot prompt, clicking the button produces no visible UI change, so the settings surface appears broken even though the action ran.

### Goals

- Keep the permission CTA bound to the same owner that manages Input Monitoring state.
- Guarantee a visible recovery path when the CoreGraphics permission request cannot grant access immediately.
- Preserve the existing enable/apply flow so toggle activation and manual permission repair stay consistent.

### Non-Goals

- Redesign the settings layout or add extra permission state.
- Introduce a custom instructional modal before opening System Settings.

## Functional Spec

- Clicking `Grant Input Monitoring Access` must always produce visible progress: either macOS grants permission through the request API or TapTick opens the relevant System Settings privacy pane.
- Enabling the keystroke overlay through its toggle should reuse the same recovery behavior when permission is missing.

## Technical Spec

- Keep permission remediation inside `KeystrokeOverlayService`, because that service already owns the CoreGraphics permission contract and is the upstream source of truth for the feature's availability.
- After `CGRequestListenEventAccess()` returns `false`, attempt to open the Input Monitoring privacy destination via `NSWorkspace`.
- Provide a fallback URL for the broader Security & Privacy settings page so the repair path still lands somewhere actionable if the more specific deep link is unavailable on a given macOS build.
