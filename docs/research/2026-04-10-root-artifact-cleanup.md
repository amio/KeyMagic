# Root Artifact Cleanup

## Foundations

### Problem

The repository root contained tracked compiler byproducts and a standalone scratch app binary/source pair that were not referenced by the package, XcodeGen project, build scripts, or documentation.

### Goals

- Remove unused root-level artifacts that do not participate in the product build.
- Prevent the same generated or scratch files from being reintroduced into version control.

### Non-Goals

- Change the application architecture or runtime behavior.
- Broaden ignore rules beyond the specific stray artifacts identified in this cleanup.

## Functional Spec

- The shipped project keeps the same build/test surface.
- Root-level generated dependency files and the standalone scratch app are no longer tracked.

## Technical Spec

- Delete `DesignTokens-2.d`, `DesignTokens-2.dia`, and `DesignTokens-2.swiftdeps` because they are compiler byproducts with no inbound references.
- Delete `test_app` and `test_app.swift` because they are standalone scratch artifacts outside the package and XcodeGen source graph.
- Add root-specific `.gitignore` entries so future local builds or ad hoc experiments do not reintroduce those files.
