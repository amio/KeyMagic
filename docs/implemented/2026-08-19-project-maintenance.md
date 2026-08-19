# Project Maintenance Hardening

Status: Implemented on 2026-08-19.

## Foundations

### Context

TapTick builds and tests successfully, but its release workflow, dependency declarations,
formatting gate, and dormant iCloud sync path contain drift that can make a future release
non-reproducible or semantically incorrect.

### Goals

- Build and package the same audited Sparkle release everywhere.
- Keep `CFBundleShortVersionString` and `CFBundleVersion` valid for normal, build-only, and
  manually dispatched releases.
- Make formatting checks deterministic and actionable without changing the existing style.
- Remove stale Xcode and asset-catalog configuration.
- Preserve shortcut deletions across iCloud last-writer-wins merges.
- Give `NSMetadataQuery` and its notification observers one main-actor lifecycle owner.

### Non-goals

- Do not enable iCloud entitlements or change its provisioning state.
- Do not enable CI for pushes to `main`.
- Do not redesign shortcut import/export or the settings UI.
- Do not split large view files solely for size.

## Functional Spec

- A shortcut deleted on one device remains deleted after merging with an older copy from
  another device.
- A shortcut edited after an older deletion wins and removes the obsolete tombstone.
- Existing local and cloud JSON arrays decode without migration loss.
- User exports remain shortcut arrays and do not expose internal sync tombstones.
- Repeated iCloud monitoring start/stop cycles do not accumulate notification observers.
- A build-only tag such as `v1.3.7+b36` packages marketing version `1.3.7` and build `36`.
- Manual builds use the versions in `project.yml`; commit metadata only labels the artifact.

## Technical Spec

### Dependency and release ownership

`Package.swift` and `project.yml` pin Sparkle 2.9.6 exactly, while the release workflow uses
the same version for `generate_appcast`. `project.yml` remains authoritative for the app's
marketing and build versions. Tags are validated against those values but never copied
verbatim into `MARKETING_VERSION`.

### Sync state

`ShortcutSyncState` is the persisted and cloud-synchronized envelope. It contains live
shortcuts plus `ShortcutDeletion` tombstones keyed by shortcut UUID and deletion date.
Decoding first accepts the envelope, then falls back to the legacy shortcut array.

Merge resolves the newest live shortcut and newest deletion independently for each UUID.
The deletion wins when its timestamp is at least as new as the live shortcut's `modifiedAt`;
otherwise the newer live shortcut wins and the stale tombstone is discarded. Tombstones are
retained indefinitely because a file-based sync protocol has no acknowledgement that every
device has observed a deletion.

`ShortcutStore` owns local live shortcuts and tombstones. UI and user import/export continue
to see only live shortcuts. `CloudSyncService` owns cloud I/O and metadata monitoring on the
main actor, including the exact observer tokens required for teardown.

### Compatibility and rollback

Legacy array files migrate in memory to an envelope and are rewritten on the next local
mutation or sync. New envelope files cannot be read by older app versions, so rolling back
after iCloud sync is re-enabled would require restoring a legacy export. This has no current
user impact because distribution iCloud entitlements remain disabled.

## Implementation Plan

1. Pin Sparkle, correct release version derivation, and align CI comments.
2. Add project formatter configuration and a strict, Xcode-aware lint command.
3. Update Xcode metadata and remove the duplicate unassigned icon.
4. Add the sync envelope and tombstone-aware merge, then migrate store persistence.
5. Fix metadata-query observer ownership and main-actor isolation.
6. Update architecture documentation and validate migration, merge, tests, lint, and Release.

## Alternatives Considered

- Encoding deletion as an optional field on `Shortcut` was rejected because a tombstone would
  need fake action and display data and could leak into UI collections.
- Inferring deletion from absence was rejected because it cannot distinguish a real deletion
  from an offline device with an older partial snapshot.
- Expiring tombstones was rejected because there is no device acknowledgement mechanism to
  prove that expiration cannot resurrect an old record.

## Trade-offs & Risks

- Tombstones grow with deletions, but shortcut volumes are small and correctness is more
  valuable than speculative compaction.
- The sync envelope is a forward-only storage format for older TapTick binaries.
- Exact dependency pins require intentional upgrades, which is desirable for release inputs.

## Validation & Rollout

- Merge tests cover newer/older deletions, recreation, legacy decoding, and persistence.
- `make lint`, YAML parsing, and `git diff --check` pass.
- The regenerated project builds the unsigned Debug app and Universal `TapTickTests` bundle successfully.
- Test execution is intentionally deferred while `main` remains excluded from CI; only the test bundle was compiled.
- Keep iCloud disabled; the new format ships dormant until provisioning is explicitly enabled.
