**Principle**: Reuse Shared Interaction Components
**Cases**: (a) Replaced the oversized General hotkey recorder with a compact shared hotkey binding control extracted from the Applications and Scripts binding UI.

**Principle**: Persist Expensive View Data Outside Ephemeral View State
**Cases**: (a) Moved the discovered applications snapshot into a shared catalog so the Applications tab reuses its first loaded list and only performs silent background refreshes afterward.

**Principle**: Separate Runtime Lifecycles From Tuning Lifecycles
**Cases**: (a) Split keystroke overlay capture shutdown from preview shutdown so disabled-state reconfiguration no longer tears down the live tuning HUD and preview can temporarily suppress event-driven text.
