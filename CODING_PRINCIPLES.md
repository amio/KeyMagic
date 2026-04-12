**Principle**: Reuse Shared Interaction Components
**Cases**: (a) Replaced the oversized General hotkey recorder with a compact shared hotkey binding control extracted from the Applications and Scripts binding UI.

**Principle**: Persist Expensive View Data Outside Ephemeral View State
**Cases**: (a) Moved the discovered applications snapshot into a shared catalog so the Applications tab reuses its first loaded list and only performs silent background refreshes afterward.

**Principle**: Separate Runtime Lifecycles From Tuning Lifecycles
**Cases**: (a) Split keystroke overlay capture shutdown from preview shutdown so disabled-state reconfiguration no longer tears down the live tuning HUD and preview can temporarily suppress event-driven text.

**Principle**: Keep Repository Inputs Separate From Local Build Artifacts
**Cases**: (a) Removed root-level compiler byproducts and a standalone scratch app from version control, then pinned them in `.gitignore` so the repo only tracks files that participate in the product graph.

**Principle**: Align Runtime Semantics With Product Contracts
**Cases**: (a) Replaced application shortcut visibility toggling with launch-or-focus activation so the executor matches the launcher behavior promised by the Applications UI and README. (b) Refined application shortcuts to hide only the frontmost activatable app instance while keeping Launch Services fallback for background and helper-process states.

**Principle**: Match Surface Area To User Decisions
**Cases**: (a) Reduced the About panel to app identity, version, update controls, and the author link so the screen only presents information a user can act on there. (b) Reworked the About layout into a centered brand block with inline update rows and compact external links so secondary controls no longer dominate the page.
