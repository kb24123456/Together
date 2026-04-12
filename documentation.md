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
- SwiftData: local projection/cache for UI
- Current shipped rebuild state:
  - pair sync lifecycle has been decoupled from `activeMode`
  - pair tasks, shared space metadata, and member profiles are moving onto the same CKSyncEngine data plane
  - shared-space display names are now being normalized around `PersistentSpace.displayName` as the primary source
  - pair metadata no longer relies on delegate-side relay repost callbacks
  - runtime legacy relay code has been retired from the app target; only SwiftData compatibility models remain so older stores can be migrated forward once

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
