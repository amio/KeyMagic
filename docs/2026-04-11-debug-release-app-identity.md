# Debug and Release App Identity

## Foundations

### Problem

TapTick currently ships a Debug build signed with `Apple Development` and a release build signed with `Developer ID Application`, while both variants present the same bundle identifier and display name. Apple documents in TN3127 that macOS privacy permissions are tracked against designated requirements, and Apple Development signatures do not share code identity with Developer ID signatures, so the system treats these builds as different apps even when their visible name matches.

### Goals

- Make the development build visibly and technically distinct from the release build.
- Ensure TCC permissions, LaunchServices registration, and local persisted state do not look like one shared app while actually behaving like two identities.
- Preserve the existing release bundle identifier and release packaging flow.

### Non-Goals

- Make Debug and release variants share privacy permissions.
- Change the release signing or notarization pipeline.

## Functional Spec

- `make run` launches `TapTick Dev.app` with a dedicated debug bundle identifier.
- The release app remains `TapTick.app` with bundle identifier `com.taptick.app`.
- Debug and release builds store local shortcut and utility data in separate Application Support directories so permission and state behavior stay aligned.

## Technical Spec

- Configure target-level Debug overrides for `PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_NAME`, and display-name-facing Info.plist substitutions.
- Add a runtime configuration helper that reads the variant-specific app-support directory name from Info.plist and centralizes identity-derived filesystem paths.
- Keep release defaults in the base target settings so archive/export/notarization commands remain unchanged.
