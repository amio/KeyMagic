# About Settings Panel

## Foundations

- Problem: `GeneralSettingsView` mixed runtime tuning with app identity, release metadata, and update controls, so the settings hierarchy blurred operational configuration with product-facing information.
- Goal: add a dedicated About pane in the sidebar that presents only TapTick's identity, version, update settings, and author links with a restrained centered layout.
- Non-goal: change Sparkle behavior, alter update feed wiring, or restructure the rest of the settings navigation.

## Functional Spec

- The settings sidebar now exposes an `About` destination.
- The About pane centers the app icon and name, shows version/build metadata directly beneath them, keeps update controls as two compact rows, and exposes the author's X link plus website link.
- The General pane keeps operational controls only: startup, appearance, global hotkeys, and data/sync.

## Technical Spec

- `SettingsView` owns the new sidebar route and injects the existing `UpdateService` into `AboutView`, so update behavior stays centralized in Sparkle-backed service code.
- `TapTickRuntimeConfiguration` now exposes version/build metadata, making app identity a reusable runtime concern instead of ad-hoc bundle reads inside individual views.
- `AboutView` uses a restrained centered composition with no enclosing cards: one brand block, two inline update rows, and a compact external-link footer, which keeps the visual weight on the product identity rather than on decorative containers.
