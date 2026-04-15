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

- Public DB: invite discovery + **pair sync data plane** (all Pair* record types)
- Private DB: single-user data (solo CKSyncEngine, unchanged)
- Shared DB: **no longer used** (CKShare-based pair sync has been replaced)
- SwiftData: local projection/cache for UI plus pending mutation storage
- Pair sync architecture (Path A — CloudKit Public DB):
  - `PairSyncService` (actor): push via `CKModifyRecords(.changedKeys)`, pull via `CKQuery` on public DB
  - `PairSyncPoller`: adaptive polling 5s→15s→30s, nudge on push notification / foreground
  - 8 Pair* record types: PairTask, PairTaskList, PairProject, PairProjectSubtask, PairPeriodicTask, PairSpace, PairMemberProfile, PairAvatarAsset
  - Soft-delete via `isDeleted/deletedAt` fields (public DB cannot truly delete other users' records)
  - `serverRecordChanged` conflict handling: merge local changedKeys onto serverRecord, retry once
  - `CKQuerySubscription` on public DB for push-driven immediate sync
  - `handleCloudKitNotification` now parses push and nudges the poller
  - Invite flow no longer creates CKShare or private zones
  - `PersistentSyncChange` lifecycle (pending→sending→confirmed/failed) reused from v2.1
  - Solo CKSyncEngine remains fully untouched

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
- Pair sync issues should be investigated in `PairSyncService` (push/pull) and `PairSyncPoller` (polling lifecycle), not in CKSyncEngine pair bridges (now dead code for pair sync).
- Composer and routines flows now derive pair behavior from the current shared space, not from `activeMode == .pair`.
- Avatar persistence tests use local-only SwiftData containers (`cloudKitDatabase: .none`) and should not be debugged as CloudKit issues.
- If an older install fails to open because of removed relay queue entities, `PersistenceController` now performs a snapshot migration into the relay-free schema instead of continuing to run those models in the main runtime.
- Shared-task correctness should be debugged against the pending mutation log (`PersistentSyncChange`) and `PairSyncPoller` state.
- After unbinding, shared projection cache and shared mutation/state rows should be gone; stale pair UI after unbind is now a real bug, not expected residual cache.
- If pair data looks stale, check: (1) `PairSyncPoller.isActive`, (2) `PersistentSyncChange` lifecycle states, (3) CloudKit Dashboard for actual Pair* records.
- If avatar display looks stale, inspect `avatarAssetID/avatarVersion` first; `avatarPhotoFileName` is now only the local cache path.
- The invite flow no longer uses CKShare or private zones. If invite acceptance fails, inspect `CloudKitInviteGateway` public DB records only.
- CloudKit Dashboard must have all Pair* record types configured with correct indexes (spaceID: Queryable, updatedAt: Queryable+Sortable) before pair sync can work.
- Final sign-off requires a fresh-install two-device TestFlight validation for: invite→pair, task sync, space rename, avatar update, offline→online recovery.
