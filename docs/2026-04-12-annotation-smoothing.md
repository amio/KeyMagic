# Screenshot Annotation Smoothing

## Foundations

- Problem: freehand annotations were rendered as raw point-to-point polylines, so uneven drag sampling produced visibly jagged strokes.
- Goal: make freehand markup feel closer to a natural pen stroke without changing the rectangle tool or adding latency-heavy post-processing.
- Non-goals: pressure simulation, variable-width brushes, stroke editing, or retroactive smoothing passes after drawing completes.

## Functional Spec

- Freehand annotation should render as a visually continuous curved stroke in both the live preview and the final copied image.
- Very dense drag samples should not create extra micro-segments or noisy kinks.
- Closed or looping freehand strokes should still be kept even when the final cursor position returns near the starting point.

## Technical Spec

- `AnnotationCanvasView` remains the owner of stroke capture and rendering so preview and export stay behaviorally identical.
- Freehand paths now run a lightweight multi-pass neighbor smoothing filter before Catmull-Rom-style cubic interpolation, which reduces drag jitter without adding a separate post-processing phase.
- Point collection filters out sub-threshold movement, and freehand commit validation uses cumulative stroke length rather than only the start/end distance.
