# Together Pair Mode V2 Implementation Plan

This file is the execution source of truth.

## Verification checklist

Core commands:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`
- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

Final validation:

- [ ] Single mode and pair mode both build, preview, and load with isolated data and correct task collaboration behavior.

## Milestones

### Milestone 01 [ ]

Scope:

- create durable control-plane files
- refactor space, pairing, and session bootstrap to support explicit single/pair mode
- add local persistence for pair space and invite state

Acceptance criteria:

- session state exposes active mode, pair context, and available spaces without relying on legacy binding-only semantics
- local services can load single-space and pair-space contexts independently

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

### Milestone 02 [ ]

Scope:

- extend task domain, persistence, repositories, and application services for pair collaboration semantics
- support assignee mode, assignment state, response messages, and permission checks

Acceptance criteria:

- pair tasks can be created, updated, responded to, and completed according to assignment rules
- repository and service behavior remains isolated by `spaceID`

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

### Milestone 03 [ ]

Scope:

- integrate pair mode into Today, task create/edit, task detail, and profile pairing flows
- implement avatar-based mode switching and pair empty states

Acceptance criteria:

- switching modes updates visible task data and top-level UI state
- pair response flows are reachable from task detail and surfaced in Today UI

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17' build`

### Milestone 04 [ ]

Scope:

- integrate pair-space behavior into Lists and Calendar
- add previews, tests, and documentation updates

Acceptance criteria:

- Lists and Calendar render pair-space data and pair-specific filters
- documentation and durable files reflect shipped behavior

Verification:

- `xcodebuild -project Together.xcodeproj -scheme Together-UnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Risks

1. Technical risk
- Risk: Existing `ItemExecutionRole` and `ItemStatus` semantics are embedded in multiple features and sync codecs.
- Mitigation: Add compatibility mapping first, then migrate feature consumers incrementally.

2. Delivery risk
- Risk: UI changes across Today, detail, profile, lists, and calendar can sprawl.
- Mitigation: Keep the pair visual language additive, preserve current layout skeletons, and verify milestone by milestone.

## Architecture notes

- `SessionStore` becomes the single source of truth for active mode and pairing context.
- `spaceID` remains the data isolation key across repositories and sync recording.
- Pair task collaboration is modeled as assignment state plus response history, not by overloading generic task status alone.
- Pair transport remains abstracted behind services and sync protocols so CloudKit can be added later without UI rewrites.

## Decision log

- Pair mode is a V2 extension and must not replace single mode as the product default.
- Pair projects are explicitly out of scope for this milestone.
- Pairing entry stays in Profile; the top-right avatar only switches active mode.
