# Together Pair Architecture Rebuild Plan v2.1

This file is the execution source of truth.

## Verification checklist

Core commands:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Final validation:

- [ ] Single-user mode still builds and behaves normally.
- [ ] Pair mode no longer depends on `activeMode` to keep sync alive.
- [ ] Pair tasks, shared-space metadata, member profile, and avatar references use one authoritative shared CloudKit data plane.
- [ ] Local SwiftData pair data acts as projection/cache only and no longer re-arbitrates shared fetched records.
- [ ] Shared mutations expose pending / sending / confirmed / failed states.
- [ ] Pair sync health is observable separately from solo sync health.
- [ ] Legacy relay compatibility paths are fully outside runtime correctness.
- [ ] Fresh-install iPhone/iPad pair flow passes avatar, shared-space rename, and shared task update validation without rollback.

## Milestones

### Milestone 01 [completed]

Scope:

- refresh durable control-plane files for the architecture rebuild
- stop coupling pair-sync lifecycle to `activeMode`
- route profile entry and pair-edit entry off binding reality instead of UI mode
- define the new pair sync source of truth

Acceptance criteria:

- `SessionStore` and Profile routing no longer disagree about whether the user is paired
- pair sync startup/shutdown follows pair relationship state, not current UI mode

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

Implementation notes:

- `SessionStore` now owns explicit apply/update methods instead of ad hoc field mutation from `ProfileViewModel` and `AppContext`.
- Pair sync startup no longer depends on `activeMode == .pair`; it follows the existence of an active pair space.
- Profile routing now keys off actual pair relationship state instead of current UI mode.
- Pair-space summary projection is now shared between `LocalSpaceService` and `LocalPairingService`.

### Milestone 02 [completed]

Scope:

- move pair data authority from "private DB + public relay copy" to CloudKit shared ownership
- publish a CKShare URL during invite creation
- accept the share on the responder device
- start pair sync against private DB for the owner and shared DB for the participant

Acceptance criteria:

- pair task data no longer requires public relay to move between the two users
- pairing metadata records persist owner/participant database role correctly

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

Implementation notes:

- Invite creation now publishes a CKShare URL and invite acceptance mounts the same shared authority plane before local pairing state is finalized.
- `AppContext` no longer treats relay polling as part of the active pair sync lifecycle.
- Verification state:
  - app build succeeds
  - unit tests pass after moving avatar persistence tests onto explicit local-only SwiftData containers
  - pair task requeue expectations and remote-change failure handling are aligned with current service behavior

### Milestone 03 [completed]

Scope:

- make pair metadata first-class sync entities (`space`, `memberProfile`) inside the same CKSyncEngine data plane
- remove the current `syncProfileToPartner -> pushProfileToRelay` architecture from the correctness path
- converge shared-space display name and partner profile reads onto one authoritative model

Acceptance criteria:

- pair task updates and pair metadata updates use the same sync transport and reliability level
- Today/Profile/Lists/Calendar read the same shared-space name source

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Implementation notes:

- `syncProfileToPartner` now records `.memberProfile` and `.space` changes onto the shared-authority `CKSyncEngine` path instead of calling the legacy relay-only metadata transport.
- `PairSpaceSummaryResolver`, `SessionStore`, and `LocalRemoteSyncApplier` now treat `PersistentSpace.displayName` as the authoritative shared-space name; `PersistentPairSpace.displayName` has been reduced to compatibility-only storage and no longer participates in runtime correctness.
- `SyncEngineDelegate` no longer keeps relay-posting callbacks or deletion-type caches; pair correctness now depends only on the shared-authority CKSyncEngine path.
- Composer and routines reload paths now key off `isViewingPairSpace` / `currentSpace?.id` instead of directly binding pair behavior to `activeMode == .pair`.

### Milestone 04 [completed]

Scope:

- migrate or disable legacy pair relay paths that are no longer needed for correctness
- keep public DB invite lookup only
- tighten docs, tests, and operator runbook

Acceptance criteria:

- pair sync correctness no longer depends on relay polling
- remaining relay code, if any, is clearly marked compatibility-only and not authoritative

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Implementation notes:

- Runtime relay files under `Together/Sync/Relay` have been removed from the app target; only migration compatibility models remain under `Together/Persistence/Legacy`.
- `PersistenceController` now opens the main SwiftData schema without relay queue entities and performs a one-time legacy-store snapshot migration when an older relay-backed store is encountered.
- `PairSpace.displayName` has been removed from the domain model so in-memory pair summaries no longer carry a second shared-space naming truth.

### Milestone 05 [completed]

Scope:

- upgrade the pair architecture from "shared data plane" to the stricter v2.1 shape
- introduce explicit binding/workspace/health separation in app state
- evolve `PersistentSyncChange` into the authoritative pending-mutation log for local shared changes
- expose shared-sync health separately from solo-sync health

Acceptance criteria:

- `SessionStore` exposes explicit pair binding state and selected workspace without requiring callers to infer from `activeMode`
- pending shared mutations persist a lifecycle state instead of being opaque queue rows
- Home/Profile can observe pair-sync health without aggregating unrelated solo errors

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Implementation notes:

- Reuse `PersistentSyncChange` as the mutation-log backing store instead of introducing a second competing persistence model.
- Keep `activeMode` as a compatibility surface while moving runtime logic toward `selectedWorkspace`.
- `SessionStore` now exposes explicit `selectedWorkspace`, `pairBindingState`, and `sharedSyncStatus` so runtime logic no longer has to infer pair state from `activeMode`.
- `PersistentSyncChange` now persists lifecycle metadata (`pending/sending/confirmed/failed`, attempted/confirmed timestamps, error text), and `LocalSyncCoordinator` exposes an explicit mutation log.
- Shared sync health now combines per-zone engine health with the persisted mutation log, so pair UI no longer relies on aggregate solo errors.
- Pair unbind now clears shared projection rows, shared mutation/state rows, pair invites, and partner profile cache artifacts so shared runtime data does not survive after the relationship ends.
- Pair-mode Today sync chrome now reads `SharedSyncStatus` directly instead of only a generic aggregate last-error string.

### Milestone 06 [completed]

Scope:

- make shared-space name and shared task state transitions use explicit pending/confirmed semantics
- stop treating shared fetched records as blindly authoritative when the same record has an outstanding local mutation
- establish CloudKit-confirmed mutation clearing and failure capture for shared entities

Acceptance criteria:

- pair task accept/complete flows no longer roll back because an older fetched shared record overwrites an unconfirmed local update
- shared space name updates no longer piggyback on profile-save callbacks

Implementation notes:

- Shared fetched records now consult the persisted mutation lifecycle, not just the in-memory engine queue, before overwriting local projection data.
- Member profile and project subtask application paths now honor pending local mutations instead of blindly accepting remote fetched values.
- Shared space name writes no longer piggyback on `syncProfileToPartner`; they are now emitted as first-class `.space` mutations through a dedicated shared-mutation callback.
- `HomeViewModel` now emits precise `.task` mutations for create/respond/complete/delete/update-style actions so `AppContext` can flush the already-recorded shared mutation directly instead of only receiving a bare `spaceID`.
- Remaining shared task entry points are being migrated off the generic workspace callback as well: Completed History restore/delete, notification completion, and composer create flows now flush explicit shared mutations instead of a blanket `spaceID` send trigger.
- `SessionStore` now retains the latest shared mutation snapshot per `(entityKind, recordID)`, and Home/Profile use that projection to render per-record `同步中 / 同步失败` state instead of only aggregate shared health.
- Home/Profile shared task and shared-space UI now also surface a short-lived `已同步` confirmed state after CloudKit acknowledgement, so users no longer jump straight from optimistic local updates back to a silent steady state.

### Milestone 07 [completed]

Scope:

- move pair member profile and avatar sync onto explicit shared-member reference semantics
- keep avatar assets as resource references, not implicit metadata transport

Acceptance criteria:

- pair profile updates share the same pending/confirmed lifecycle and health reporting as pair tasks
- avatar updates do not overload `nil` / empty metadata semantics

Implementation notes:

- `User`, `PersistentUserProfile`, and `PersistentPairMembership` now carry `avatarAssetID/avatarVersion` end-to-end.
- UI read paths are moving toward `avatarAssetID` as the canonical shared reference, with `avatarPhotoFileName` retained only as a local cache file name.
- `EditProfileViewModel` now reads and compares avatar state through `avatarCacheFileName`, so asset-backed and file-backed avatars share one presentation path.
- Compatibility-only profile apply paths now repair `avatarAssetID` alongside cached avatar file names instead of leaving metadata/file drift behind.
- `syncProfileToPartner` and `onProfileSaved` no longer carry an `includeAvatar` transport switch; shared member-profile submission now relies on persisted `avatarAssetID/avatarVersion` state instead of ad hoc call-site flags.
- `SyncEngineDelegate.makeMemberProfilePayload(...)` is now the single place that derives member-profile avatar semantics; a profile with `avatarAssetID` but no local blob is treated as a preserved avatar reference, not as an implicit delete.
- `syncProfileToPartner(user:)` has been reduced to a pure `.memberProfile` shared-mutation submission path and no longer rewrites the private profile store as a side effect.
- `MemberProfileRecordCodable.Profile` is now metadata-only: shared authority is driven exclusively by `avatarAssetID/avatarVersion/avatarDeleted`, and shared member-profile records no longer carry avatar bytes.
- `SyncEngineDelegate` and `PairSyncBridge` now apply shared member profiles by explicit asset/delete semantics: only `avatarDeleted` clears an avatar, while asset references update metadata even when no local cache file is present.
- `makeMemberProfilePayload(...)` no longer inspects `avatarPhotoData`; a blob-only local cache is treated as legacy repair state, and shared payload semantics now depend only on `avatarAssetID/avatarPhotoFileName`.
- `LocalUserProfileRepository.mergedUser(...)` no longer treats `avatarPhotoData` as an authoritative merge-time signal; blob repair now happens only inside `repairAvatarMetadataIfNeeded(...)`, after which runtime reads rely on normalized avatar reference/file metadata.
- `avatarAsset` is now a first-class shared mutation entity. Profile saves submit `avatarAsset + memberProfile`, and shared avatar bytes travel through `AvatarAssetRecordCodable` instead of piggybacking on member-profile metadata.
- Shared avatar apply now persists incoming asset bytes into the local cache file derived from `avatarAssetID`, then refreshes any local user/member projections that reference that asset.
- Shared member-profile payloads no longer inspect local blob storage at all; runtime shared avatar correctness now depends only on `avatarAsset` transport plus `avatarAssetID/avatarVersion/avatarDeleted` metadata.

### Milestone 08 [completed]

Scope:

- finish compatibility cleanup and migration boundaries for the v2.1 architecture
- document shared/private/public database responsibilities and operator troubleshooting against the new state machine

Acceptance criteria:

- runtime correctness does not depend on `PersistentPairSpace` compatibility mirrors
- docs describe the v2.1 state model, mutation model, and verification flow
- legacy public-profile/runtime compatibility code is fully outside runtime correctness

Implementation notes:

- `PersistentPairSpace.displayName` remains migration-only storage; runtime reads now normalize around `PersistentSpace.displayName` and `SessionStore.pairSpaceSummary`.
- The legacy public-profile runtime path has been fully removed: `CloudKitProfileRecordCodec`, public profile pull helpers, and explicit repair APIs are no longer part of the running app.
- `LocalRemoteSyncApplier` is back to task-only public-db apply behavior, so pair member profile/avatar correctness now depends solely on the shared-authority CKSyncEngine path.
- `CloudKitSyncGateway` has retired legacy public-profile writes entirely; the public member-profile path is now read/repair-only and cannot be used as a runtime correctness fallback.
- Legacy public-profile backfill has been removed from `RemoteSyncPayload`; `LocalRemoteSyncApplier` now exposes an explicit `repairLegacyProfiles(...)` entry point so compatibility repair can no longer piggyback on normal remote task apply cycles.
- `LocalRemoteSyncApplier` and `CloudKitProfileRecordCodec` remain repair-only compatibility boundaries; current shared-authority avatar references are no longer derived from or overwritten by legacy public-profile runtime payloads.
- `CloudKitProfileRecordCodec` no longer exposes a legacy member-profile record writer; the public-profile codec is now strictly read/repair-only and cannot be reused as a runtime write path.
- Unbind regression coverage now explicitly verifies that shared projection/state rows are removed while the current user's private profile record remains intact.
- `TogetherTests` is now `@MainActor`-isolated so Swift 6 actor-safety tightening no longer blocks the test target from compiling while the runtime architecture work continues.

## Risks

1. Architecture risk
- Risk: Existing pair data is split across `PersistentSpace`, `PersistentPairSpace`, `PersistentPairMembership`, and relay payload conventions.
- Mitigation: first establish one authority path, then progressively demote redundant mirrors instead of deleting them blindly.

2. CloudKit risk
- Risk: owner/private DB and participant/shared DB behavior can diverge subtly.
- Mitigation: isolate database selection in one coordinator path, use system-provided shared zone metadata, and avoid local re-arbitration of shared fetched records.

3. Delivery risk
- Risk: pair runtime currently mixes UI-mode state, binding state, and sync-health state.
- Mitigation: separate these concerns explicitly before deeper shared-data refactors.

## Architecture notes

- Public DB is invite discovery only.
- Pair tasks and pair metadata should live in one shared CloudKit authority, not in per-user copies replicated via relay.
- `activeMode` is a presentation compatibility surface only; runtime logic should move toward `selectedWorkspace`.
- Local SwiftData remains a projection/cache layer for UI and offline use.
- Pending mutations need explicit lifecycle state and must not be silently overwritten by shared fetches.
- Avatar transport should move toward asset/reference semantics; metadata-only updates must never imply avatar deletion.

## Decision log

- The current pair relay architecture is no longer the target state.
- Pair-mode stability takes precedence over preserving the existing relay wiring.
- The first implementation milestone will prioritize source-of-truth and lifecycle fixes before deeper model cleanup.
