# CORE GUIDELINES

## Workflow
- **Post-Development**:
  - Refactor for maximum simplicity; resolve all diagnostic errors (auto-apply safe fixes).
  - Document logic using **in-code comments** (not external docs).
  - Provide a **Conventional Commits** draft (English, code block) for the change set.

## Development Principles
- **Simplicity & MVP**: Focus on minimal design; avoid over-engineering.
- **Proactive Execution**: Analyze "why" over "how"; propose optimizations/alternatives instead of passive task completion.
- **Clean Architecture**: Ensure High Cohesion, Low Coupling (SOLID); prioritize readability over "just working."
- **Native-First**: Prefer Platform APIs over simulations.

## Coding Standards
- **Modernity**: Prioritize latest features and modern MacOS APIs.
- **Structure**:
  - Max **6 levels** of indentation; extract functions/variables to flatten logic.
  - Use **local components** for file-specific UI; split complex ternary ops (>3 lines).
  - Move large inline strings (prompts/constants) to utility functions.
  - Adopt the "Newspaper Metaphor": Place the primary exported function at the top of the file. Arrange internal helper functions below it, ordered by their sequence of invocation.
- **Rules**:
  - **No formatting**: Do not fix indentation/style (handled by external tools).
  - **No example files**: Provide usage examples directly in chat.

## Design Philosophy
- Meet the standards of the Apple Design Awards, prioritizing intuitive interaction, exceptional craftsmanship, and profound emotional resonance.
- Embrace the bleeding edge, utilizing the latest SDKs, APIs, and modern UI components to build a state-of-the-art interface.

## Documentation
- **Quality**: Focus on "purpose," not a list of changes. Use **English** only.

## Technical Design Framework

- **The Three-Layer Onion**:
  1. **Foundations**: Define the problem statement, goals/non-goals, and requirements.
  2. **Functional Spec**: Detail the system's behavior from an external perspective.
  3. **Technical Spec**: Describe internal implementation and logic.
- **Top-Down Logic**: Each layer must justify the next. Fix flaws in the problem statement or functional spec *before* moving to technical details to avoid ineffective implementation.
- **Decision Rationale**: Do not just present the final spec. Document alternatives considered and provide clear rationale for chosen solutions to enable meaningful review.

# PROJECT ARCHITECTURE

> **Note for agents**: This section is maintained by agents. If a task changes any aspect of the architecture described here, update this section accordingly — keep it accurate, concise, and informative for agent's future work.
