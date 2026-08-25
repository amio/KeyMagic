# Large Type

## Context & Goals

`UtilityID.largeType` already reserves a place in the Utilities catalog, while `UtilitiesController` and `HotkeyService` own native-utility configuration and the shared Carbon hotkey namespace. Large Type should become a production utility in that existing model.

The feature opens a full-screen, dark, blurred input surface from a configurable global hotkey. It renders entered text at the largest readable size, progressively allows additional wrapped lines as the single-line size becomes too small, and can transition to a split text/QR-code presentation.

## Requirements & Invariants

- The default hotkey is `cmd + option + control + L`.
- The utility has persisted enabled state, hotkey, font family, foreground color, and background color.
- Triggering the hotkey opens an input-focused full-screen overlay; `Escape` or the hotkey closes it.
- The overlay blurs the content behind a dark configurable mask and centers the text.
- Empty input shows a blinking caret at the center.
- Text starts on one line. If its fitted line height is below half the screen height, wrapping may use two lines; if it remains below one third, it may use three, continuing by the same rule.
- A subtle 20-point QR icon at bottom center switches non-empty text into an unframed right-side QR code with text on the left. The layout transition is animated without bounce and is reversible.
- A standalone `Option` key press also switches modes. Option-modified shortcuts must retain their normal behavior without switching the presentation. The circular button reveals the key hint on hover.
- Large Type stays in the shared conflict-checked hotkey namespace and outside the user shortcut schema.
- The presentation owner must return focus to the previously active app when the user explicitly dismisses the overlay.

## Proposed Solution

`UtilitiesController` remains the configuration and routing owner. `LargeTypeConfiguration` is added to the forward-compatible `utilities.json` envelope, and its enabled hotkey is exposed through the existing reserved-hotkey API.

`LargeTypeService` owns one process-lifetime presentation session:

1. Resolve the screen under the pointer, remember the foreground application, and activate one key-capable borderless panel covering that screen.
2. Place an active `NSVisualEffectView` behind a SwiftUI presentation so the desktop and application content are blurred before the configured color tint is applied.
3. Keep a visually hidden `NSTextView` as first responder. This preserves native text input, selection, paste, undo, and input-method composition while SwiftUI renders the presentation text.
4. Use `LargeTypeLayoutEngine` to measure candidate fonts. It selects the smallest allowed line count whose fitted line height reaches `screenHeight / (lineCount + 1)`, then renders at that line count's maximum fitting size.
5. Generate QR codes locally with Core Image. The SwiftUI surface animates the text frame, font size, and QR-code insertion with an ease-out curve.

The service alone owns panel visibility, session text, QR mode, first-responder focus, and focus restoration. Settings never create a second runtime presentation.

## Implementation Plan

1. Add the persisted configuration, catalog availability, hotkey reservation, conflict handling, and utility routing.
2. Add the full-screen service, native text-input bridge, layout engine, blurred presentation, QR renderer, and dismissal lifecycle.
3. Replace the planned Large Type placeholder with settings for enablement, hotkey, font, and colors.
4. Add focused tests for configuration migration/persistence, hotkey reservation, and progressive wrapping behavior.
5. Format, lint, test, build, and launch the app.

## Trade-offs & Risks

- A QR code has finite capacity. Text beyond Core Image's QR capacity remains visible, while the QR side reports that the text is too long instead of silently truncating it.
- The overlay targets one screen—the screen under the pointer—matching the existing transient-overlay convention. It does not cover every connected display at once.
- Font availability differs across Macs. A missing persisted family falls back to the system font without rewriting the user's stored choice.
- Native text input is kept separate from visual text rendering. This adds a small bridge but avoids reimplementing input methods and editing commands.

## Validation & Rollout

- Decode older `utilities.json` files without a Large Type entry and supply defaults.
- Verify enable/disable registration and hotkey conflicts through controller tests.
- Verify short text remains single-line and long text progressively receives additional lines without exceeding its layout region.
- Manually validate activation, typing (including composed input), Escape/hotkey dismissal, blur, caret animation, QR generation, split-layout animation, color/font changes, and focus restoration in the launched Debug app.
