# DEVELOPMENT PROTOCOL — TapTick

## 1. Workflow & Strategy

### Execution Phase

**Pre-Task**: Before executing any assigned task, agents must conduct a thorough analysis of the relevant codebase to understand the context and potential impact of their changes. This includes:
  - **Contextual Audit**: Perform a comprehensive audit of relevant code for context and impact.
  - **Proactive Ownership**: Prioritize "why" over "how." Challenge sub-optimal architectures rather than passive execution.
  - **Strategic Research**: Formulate the optimal approach considering system-wide implications. For complex tasks, onsolidate insights into `docs/{date}-{topic}.md`.

**Post Task**: After completing the assigned task, agents must:
  - **Refinement**: Review the complete changeset; refactor for maximum simplicity and resolve all diagnostic errors.
  - **Commit Draft**: End every response with an updated English **Conventional Commits** block.

### Design Framework (Three-Layer Onion)
1. **Foundations**: Define problem, goals/non-goals, and requirements.
2. **Functional Spec**: Detail external behavior.
3. **Technical Spec**: Describe internal logic and rationale.
*Note: Each layer must justify the next; fix upstream flaws before technical implementation.*

## 2. Development Principles

- **Simplicity (MVP)**: Eliminate over-engineering and "Trivial Forwarding" (Middle Man). Ensure every function adds value or refactor to reduce call depth.
- **Clean Architecture**: Enforce SOLID principles; prioritize cohesion and long-term readability.
- **Native-First**: Use platform APIs (Electron `nativeTheme`, Web Popover/Anchor) and GPU-accelerated CSS over JS-heavy simulations.
- **Performance-By-Design**: Optimize for real-world usage patterns; avoid premature optimization but identify and address bottlenecks early.
- **Use Edge APIs**: Leverage cutting-edge features (e.g., React 19 Actions, View Transitions) to enhance UX and maintain modern codebase.

## 3. Technical Standards

- **Stack**: Strict TypeScript (zero `any/as`), semicolon-free, **styled-jsx** only (no Tailwind).
- **Modernity**: React 19 (Actions/use), Node.js test runner, ES2023/2024, View Transitions.
- **Logic Structure**:
  - **Newspaper Metaphor**: Primary export at top; helpers follow in execution sequence.
  - **Organization**: Localize file-specific components; move large strings/prompts to constants.
- **Constraints**:
  - No manual reformatting. Use tools like `npm run format/lint`.
  - No standalone example files. All code must be production-ready and integrated into the system.

## 4. Documentation & Comments

- **In-Code Focus**: Document logic intent within source code, not external docs.
- **Language & Style**: English only. Use single-line `/** */` for types and **TSDoc** (`@param`, `@returns`) for exports.
- **Synchronization**: Maintain strict alignment between code comments and `README.md`.






# ARCHITECTURE BLUEPRINT

> ⚠️ **CRITICAL DIRECTIVE FOR ALL AGENTS** ⚠️
> This section is the **Mind Map** for the system's core structure and is maintained entirely by agents.
> **Mandatory Action**: Update this section immediately if your task alters the tech stack, product logic, or file responsibilities.
>
> **Content Focus & Style**: Keep it lean. Each concept must be 1-2 sentences. Only three categories are permitted:
>
> 1. **Core Tech Stack**: Critical selections and versions.
> 2. **Product Logic**: Core concepts and their interaction patterns.
> 3. **Component Map**: Key components and the specific files responsible for them.
>
> Failure to maintain this skeleton will degrade future agents' navigation and decision-making capabilities.

## Core Tech Stack

- **Language & UI**: Swift 6 (strict concurrency) + SwiftUI, targeting macOS 15+.
- **Build System**: XcodeGen (`project.yml`) generates `TapTick.xcodeproj`; `Makefile` drives all dev/CI tasks.
- **Package Structure**: SPM monorepo — `TapTickKit` library (`Sources/TapTickKit`) + `TapTick` app (`Sources/TapTick`).
- **Auto-Update**: Sparkle 2 (`SPUStandardUpdaterController`) with EdDSA-signed appcast at `https://amio.github.io/TapTick/appcast.xml`.
- **CI**: GitHub Actions (`.github/workflows/build.yml`) — unit tests on every push; archive → notarize → DMG → GitHub Release on `v*` tags.

## Product Logic

- **Global Hotkeys**: Carbon `RegisterEventHotKey` API (no Accessibility permission needed); each `KeyCombo` is registered individually, including the reserved settings-window toggle hotkey, and fires a targeted callback. When that settings surface is dismissed through its shared hide path, TapTick restores focus to the app that was frontmost before the panel was opened when possible.
- **Utilities**: Native utilities live outside the user shortcut model, with their own persisted settings, reserved hotkeys, and permission-aware runtime services. Each utility can register multiple named hotkey actions (featureID + action string) through `UtilitiesController.reservedHotkeys()`, and permission-gated utilities own both the initial request and the System Settings recovery path.
- **Capture & Mark**: Two capture flows — "Capture to Clipboard" (`screencapture -ic`, no UI) and "Capture & Mark" (`screencapture -i` to temp file → borderless annotation window with freehand/rect drawing → Return copies composited image to clipboard). Default hotkeys ⌃⌥⌘N / ⌃⌥⌘M. Tapping ⌥ toggles the draw tool, holding ⌥ temporarily swaps to the other tool, and Tab cycles annotation color through a six-color palette.
- **Shortcuts**: Each `Shortcut` has a `KeyCombo`, a `ShortcutAction` (launch app / run inline script / run script file), and metadata (`isEnabled`, `createdAt`, `modifiedAt`, `lastTriggeredAt`). Application shortcuts hide the target only when its activatable instance is already frontmost; otherwise they unhide/focus a running app or start it through Launch Services.
- **Runtime Identity**: The Debug app is intentionally isolated as `TapTick Dev` (`com.taptick.app.dev`) while release remains `TapTick` (`com.taptick.app`), so macOS permissions and local app-support storage match the actual signing identity instead of pretending to be shared.
- **Installed App Discovery**: The Applications tab keeps the first discovered app snapshot in a shared in-memory catalog for the rest of the session, while later tab visits trigger silent background refreshes instead of returning to a loading-only state.
- **iCloud Sync**: Optional, uses ubiquity container `iCloud.com.taptick.app`; last-writer-wins merge by UUID + `modifiedAt`; currently disabled pending provisioning profile.
- **Persistence**: User shortcuts and utility settings persist under a variant-specific Application Support directory (`TapTick` for release, `TapTick Dev` for Debug); optional cloud sync still targets `iCloud.com.taptick.app/Documents/shortcuts.json`.
- **Script Execution Logging**: Hotkey-triggered and in-panel test script executions both capture stdout+stderr via `Pipe`, store the last `ScriptExecutionLog` per shortcut ID in an in-memory `ScriptLogStore`, and reuse that same log for the subtitle HUD preview plus the Scripts settings `Output` sheet; the HUD is intentionally a compact tail preview while the sheet shows the full formatted log.

## Component Map

- **App entry point**: `Sources/TapTick/App/TapTickApp.swift` — `@main`, `AppState` (shared singleton owning all services, the utilities controller, and the settings window reference), `AppDelegate` (lifecycle, startup wiring, settings-window toggle, menu bar init, hotkey bootstrap), Settings Window scene.
- **Hotkey engine**: `Sources/TapTickKit/Services/HotkeyService.swift` — registration, Carbon event dispatch, reserved settings-window/built-in hotkeys, shortcut conflict checks, and recorder suspension.
- **Runtime identity**: `project.yml`, `Resources/Info.plist`, and `Sources/TapTickKit/Services/TapTickRuntimeConfiguration.swift` — define Debug vs release bundle identity, display name, and variant-specific Application Support routing.
- **Data layer**: `Sources/TapTickKit/Services/ShortcutStore.swift` — CRUD, disk I/O, cloud sync coordination, and runtime-aware local storage routing.
- **Utility runtime**: `Sources/TapTickKit/Services/UtilitiesController.swift` and `Sources/TapTickKit/Services/KeystrokeOverlayService.swift` — utility persistence, keystroke overlay permission flow, Input Monitoring settings recovery, global key capture, and floating HUD presentation. `Sources/TapTickKit/Services/ScreenshotService.swift` — orchestrates `screencapture` CLI for two modes (clipboard-only and capture-and-mark) and manages the annotation preview window lifecycle.
- **Cloud sync**: `Sources/TapTickKit/Services/CloudSyncService.swift` — NSMetadataQuery monitoring, upload/download, merge algorithm.
- **Action execution**: `Sources/TapTickKit/Services/ShortcutExecutor.swift` — app hide/focus/launch via activation-capable running instances with Launch Services fallback, plus the shared script runner used by both hotkey dispatch and the Scripts test-run button; captures script output and fires `onScriptCompleted` callback with a `ScriptExecutionLog`.
- **Script logging & subtitle**: `Sources/TapTickKit/Services/ScriptLogStore.swift` — `ScriptExecutionResult`, `ScriptExecutionLog`, and `@Observable ScriptLogStore` keeping the last log per shortcut (in-memory only) plus the shared detail/subtitle formatting rules. `Sources/TapTickKit/Services/ScriptOutputPresenter.swift` — borderless `NSPanel` subtitle overlay (dark translucent pill, monospaced text, 4 s hold + fade-out) positioned at ~15 % from screen bottom, red-tinted background for errors.
- **Settings UI**: `Sources/TapTickKit/Views/SettingsView.swift` (sidebar nav) → `GeneralSettingsView`, `ApplicationsView`, `ScriptsView`, `UtilitiesView`, `AboutView`; `AboutView` owns app identity and Sparkle update controls, while `UtilitiesView` owns the scalable utility directory, the keystroke overlay settings panel, and the Capture & Mark settings panel.
- **Screenshot annotation UI**: `Sources/TapTickKit/Views/ScreenshotPreviewWindow.swift` — titled floating `NSPanel` (`.titled | .closable | .fullSizeContentView`) with `NSVisualEffectView` (`.sidebar` material) blur background, a SwiftUI `AnnotationToolbar` placed directly in the titlebar zone via `NonDraggableHostingView` (constrained top→safeArea.top, leading 76pt past traffic lights); left group: custom segmented mode switch + keycap "⌥", color circle indicator + keycap "TAB"; right group: "Copy" pill button + keycap "↩". `AnnotationCanvasView` overrides `mouseDownCanMoveWindow = false` to prevent draw gestures from dragging the window; `AnnotationToolbarModel` (@Observable) bridges state between canvas and toolbar; tapping ⌥ toggles mode, holding ⌥ temporarily swaps mode, Tab cycles color, Return composites and copies to clipboard, Escape cancels, ⌘Z undoes.
- **Applications catalog UI**: `Sources/TapTickKit/Views/ApplicationsView.swift` — shared discovered-app cache, background rescan policy, unavailable-app section, and per-app hotkey binding rows.
- **Hotkey input UI**: `Sources/TapTickKit/Views/Components/HotkeyBindingControl.swift` owns the compact shared hotkey recording/binding interaction reused by settings surfaces.
- **Menu bar UI**: `Sources/TapTickKit/Views/MenuBarController.swift` — native `NSStatusItem` + `NSMenu`; Observation-driven rebuild on shortcut changes; UserDefaults KVO show/hide; native key equivalent glyphs.
- **Bundle IDs**: Debug app `com.taptick.app.dev`; release app `com.taptick.app`; iCloud container `iCloud.com.taptick.app`.
