# Together Pair Architecture Rebuild Plan

This file is the execution source of truth.

## Verification checklist

Core commands:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Final validation:

- [ ] Single-user mode still builds and behaves normally.
- [ ] Pair mode no longer depends on `activeMode` to keep sync alive.
- [ ] Pair tasks and pair metadata share one authoritative CloudKit data plane.
- [x] Pair profile edits and shared space name edits are no longer transported through the legacy relay-only path.

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

## Risks

1. Architecture risk
- Risk: Existing pair data is split across `PersistentSpace`, `PersistentPairSpace`, `PersistentPairMembership`, and relay payload conventions.
- Mitigation: first establish one authority path, then progressively demote redundant mirrors instead of deleting them blindly.

2. CloudKit risk
- Risk: owner/private DB and participant/shared DB behavior can diverge subtly.
- Mitigation: isolate database selection in one coordinator path and keep codecs/database routing centralized.

3. Delivery risk
- Risk: full deletion of relay code in one pass may break current production-like paths.
- Mitigation: migrate correctness path first, then retire compatibility code after validation.

## Architecture notes

- Public DB is invite discovery only.
- Pair tasks and pair metadata should live in one shared CloudKit authority, not in per-user copies replicated via relay.
- `activeMode` is a presentation choice, not a backend sync switch.
- Local SwiftData remains a projection/cache layer for UI and offline use.
- Avatar transport should move toward asset/reference semantics; metadata-only updates must never imply avatar deletion.

## Decision log

- The current pair relay architecture is no longer the target state.
- Pair-mode stability takes precedence over preserving the existing relay wiring.
- The first implementation milestone will prioritize source-of-truth and lifecycle fixes before deeper model cleanup.
