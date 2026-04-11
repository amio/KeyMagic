# Keystroke Overlay Permission Layout

## Foundations

### Problem

The keystroke overlay settings row needs a persistent badge footprint so the toggle row does not shift when status appears or disappears. The existing placeholder uses a hidden `Active` pill, then paints the real permission warning as an overlay, which makes the long permission copy render inside a short badge footprint and truncate. The permission call-to-action and recovery guidance also live in separate form rows, which breaks the relationship between the action and the explanation.

### Goals

- Preserve a stable badge slot so the toggle row does not change height when status changes.
- Let every rendered status badge fit fully inside that slot.
- Present the permission grant action and the recovery guidance as one coherent row.
- Preserve graceful behavior when the settings window narrows.

### Non-Goals

- Change the keystroke overlay permission flow or underlying runtime services.
- Introduce a new settings section or additional persisted state.

## Functional Spec

- The keystroke overlay title row keeps a stable status footprint and shows the current runtime badge without truncating the `Input Monitoring Required` state.
- When permission is missing, the grant button and recovery guidance appear together as one settings row.
- If the pane becomes too narrow for the combined row, the layout may fall back to a stacked presentation instead of clipping controls.

## Technical Spec

- Keep a hidden placeholder badge in the toggle label so status transitions do not change the row's measured height.
- Measure that placeholder from the widest known status (`Input Monitoring Required`) and overlay the active runtime badge on top of the reserved slot.
- Mark badges as fixed-size capsules so form compression does not collapse their text.
- Replace the two permission form rows with a single `ViewThatFits`-backed helper that prefers a horizontal button-plus-guidance row and degrades to a vertical stack only when width is genuinely insufficient.
