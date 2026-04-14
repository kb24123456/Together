# Together Documentation

This file should match the current repo state.

## What this project is

- An Apple-platform task app centered on single-user productivity, with pair collaboration being rebuilt on top of a CloudKit shared-authority architecture.

## Local setup

- Xcode 26.2+
- iOS 18+ simulator runtime
- Open `Together.xcodeproj`
- Build the `Together` scheme

## Verification commands

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Current architecture target

- Public DB: invite discovery only
- Private DB: single-user data and owner-side pair zone
- Shared DB: participant-side access to the same pair authority via CKShare
- SwiftData: local projection/cache for UI plus pending mutation storage
- Current shipped rebuild state:
  - pair sync lifecycle has been decoupled from `activeMode`
  - pair tasks, shared space metadata, and member profiles are moving onto the same CKSyncEngine data plane
  - shared-space display names are now being normalized around `PersistentSpace.displayName` as the primary source
  - pair metadata no longer relies on delegate-side relay repost callbacks
  - runtime legacy relay code has been retired from the app target; only SwiftData compatibility models remain so older stores can be migrated forward once
  - v2.1 now separates pair binding state, selected workspace, and shared sync health, and upgrades `PersistentSyncChange` into the explicit mutation log
  - shared sync health is now derived from both CKSyncEngine zone health and the persisted mutation log
  - pair unbind now clears shared projection rows, shared mutation/state rows, related invites, and partner profile cache artifacts instead of only ending the relationship record
  - shared fetched records now preserve outstanding local pair mutations instead of blindly overwriting local projection state
  - shared-space renames now enqueue a dedicated `.space` mutation instead of riding along the profile metadata path
  - Home task state changes now emit precise shared `.task` mutations so send/health refresh can run off the actual changed record instead of a generic workspace callback
  - Completed History, notification completion, and composer task creation are now moving onto that same explicit shared-mutation flush path instead of a blanket workspace send
  - avatar identity is now being normalized around `avatarAssetID/avatarVersion`, with `avatarPhotoFileName` demoted to a local cache concern instead of the shared source of truth
  - shared member-profile submission no longer depends on an `includeAvatar` call-site flag; avatar semantics are derived from persisted `avatarAssetID/avatarVersion` state instead
  - shared member-profile records are now metadata-only; shared correctness is driven by `avatarAssetID/avatarVersion/avatarDeleted`, and avatar bytes no longer travel through shared member-profile records
  - shared member-profile encoding no longer inspects local avatar blob storage; if no avatar reference exists, the shared payload is treated as an explicit avatar removal regardless of cached repair bytes
  - legacy profile apply paths are now repair-only and must not overwrite current shared-authority space names, nicknames, or avatar references
  - the legacy public CloudKit gateway no longer injects member-profile payloads into normal task pull cycles; legacy profile reads are explicit repair/migration operations only
  - the legacy public CloudKit gateway can no longer write member-profile records at all; that path is now strictly read/repair-only and is no longer available as a runtime fallback
  - pair-only sync chrome now reads `SharedSyncStatus` directly, so pending shared mutations and shared send/fetch failures are no longer hidden behind a generic aggregate sync error

## Demo flow

- Launch in single mode and verify Today, Lists, and Calendar show only single-space data.
- Pair two devices through Profile invite flow.
- Confirm pair sync remains active even when the UI is showing single mode.
- Edit pair space metadata and pair tasks, then verify both devices converge.

## Repo structure

- `Together/App`: bootstrap, session, routing, top-level composition
- `Together/Domain`: entities, enums, protocols, state machines
- `Together/Services`: repositories and local/cloud service implementations
- `Together/Features`: SwiftUI features for Today, Lists, Projects, Calendar, Profile, and shared UI
- `Together/Persistence`: SwiftData models and container setup
- `Together/Sync`: CloudKit invite flow, CKSyncEngine, codecs, and legacy-store migration helpers

## Troubleshooting

- If build errors mention missing simulator, adjust the destination device name to an installed iPhone simulator.
- If CloudKit pairing behavior looks stale after schema changes, use a fresh simulator install or a new iCloud test account before assuming the latest code path is wrong.
- During the architecture rebuild, do not assume relay paths are authoritative unless `plans.md` explicitly says so.
- Pair metadata issues should now be investigated first in the CKSyncEngine shared-authority path, not in legacy relay callbacks.
- Composer and routines flows now derive pair behavior from the current shared space, not from `activeMode == .pair`.
- Avatar persistence tests use local-only SwiftData containers (`cloudKitDatabase: .none`) and should not be debugged as CloudKit issues.
- If an older install fails to open because of removed relay queue entities, `PersistenceController` now performs a snapshot migration into the relay-free schema instead of continuing to run those models in the main runtime.
- Shared-task correctness should be debugged against the pending mutation log and the pair/shared zone health, not against aggregate "any sync" UI indicators.
- After unbinding, shared projection cache and shared mutation/state rows should be gone; stale pair UI after unbind is now a real bug, not expected residual cache.
- If pair metadata or shared task updates look stale after a fetch, inspect the persisted mutation lifecycle first; pending/sending/failed local mutations now intentionally block remote overwrite until they are confirmed or cleared.
- If avatar display looks stale, inspect `avatarAssetID/avatarVersion` first; `avatarPhotoFileName` is now only the local cache path and should not be treated as the shared source of truth.
- If a shared member profile unexpectedly clears an avatar, inspect the derived `MemberProfileRecordCodable.Profile` payload first; only `avatarDeleted` should clear an avatar, and an asset reference without a local cache file must remain a preserved reference.
- If legacy public-profile data appears during migration, it should only repair missing local cache/reference holes; if it changes an already-synced shared nickname, shared space name, or avatar reference, that is now a real bug.
