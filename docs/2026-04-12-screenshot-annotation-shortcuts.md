# Screenshot Annotation Shortcuts

## Foundations

- Problem: the previous shortcut layout split annotation switching across `Tab`, hold-`Option`, and `Option`+`Tab`, which made the keyboard model harder to remember.
- Goal: collapse screenshot preview mode changes onto a single key while preserving the temporary swap behavior for quick one-off marks.
- Non-goals: changing annotation persistence, adding new drawing tools, or introducing multi-key mode chords.

## Functional Spec

- Tapping `Option` toggles the persisted drawing mode between freehand and rectangle.
- Holding `Option` temporarily swaps to the opposite mode, and releasing it restores the persisted selection.
- Pressing `Tab` cycles annotation color regardless of the currently selected drawing mode.

## Technical Spec

- `ScreenshotPreviewWindow` owns the `Option` short-press vs hold discrimination so the gesture is decided once at the preview boundary instead of being inferred from multiple controls.
- `AnnotationToolbarModel` continues to separate persisted mode from effective mode, which lets temporary overrides stay visual-only and keeps saved preferences stable.
- `AnnotationCanvasView` snapshots the effective mode at mouse-down, so a stroke keeps its original semantics even if the user presses or releases `Option` mid-draw.
