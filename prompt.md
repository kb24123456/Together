# Together

You are Codex acting as the implementation partner for Together. Deliver a complete dual-mode result for this project.

Core goals

- Add a true pair mode without breaking the current single-user task flow.
- Keep single-space and pair-space data fully isolated.
- Make pair mode available through avatar-based mode switching and profile-based pairing management.
- Support shared pair-space task collaboration across Today, Lists, Calendar, create/edit, and detail flows.

Hard requirements

- Follow `PRODUCT_SPEC.md`, `DEVELOPMENT_GUIDELINES.md`, `DESIGN_GUIDELINES.md`, and `AGENTS.md`.
- Keep single mode as the default startup mode.
- Do not implement pair projects in this milestone.
- Prefer SwiftUI, SwiftData, and modern Swift concurrency.
- Keep pair sync transport mockable; do not ship real CloudKit transport in this milestone.

Deliverable

- Working pair-mode architecture, UI integration, previews, tests, and documentation aligned with the repo state.

Project spec

- Pair mode uses an independent shared data space after pairing succeeds.
- Users pair through profile, then switch modes from the top-right avatar control.
- Pair tasks support assignee modes for self, partner, or both.
- Partner-assigned tasks require accept, decline, or snooze with an optional short message.
- Pair mode UI should feel warmer than single mode while staying native and restrained.

Process requirements

1. Create `plans.md` before broad implementation.
2. Implement milestone by milestone.
3. Keep `documentation.md` aligned with shipped behavior.

Start now.
Do not begin broad coding until `plans.md` exists and is coherent.
