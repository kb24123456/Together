# Together Documentation

This file should match the current repo state.

## What this project is

- An iPhone-first task app centered on single-user productivity, with pair collaboration being added as a V2 shared-space extension.

## Local setup

- Xcode 26.2+
- iOS 18+ simulator runtime
- Open `Together.xcodeproj`
- Build the `Together` scheme

## Verification commands

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Demo flow

- Launch in single mode and verify Today, Lists, and Calendar show only single-space data.
- Open Profile and inspect pairing state.
- Switch to pair mode from the top-right avatar after pairing is available.
- Create a pair task for self, partner, and both; verify response and visibility behavior.

## Repo structure

- `Together/App`: bootstrap, session, routing, top-level composition
- `Together/Domain`: entities, enums, protocols, state machines
- `Together/Services`: repositories and local/mock service implementations
- `Together/Features`: SwiftUI features for Today, Lists, Projects, Calendar, Profile, and shared UI
- `Together/Persistence`: SwiftData models and container setup
- `TogetherTests`, `TogetherUITests`: verification targets

## Troubleshooting

- If build errors mention missing simulator, adjust the destination device name to an installed iPhone simulator.
- If previews or tests show stale local data, delete the app from the simulator and rerun.
