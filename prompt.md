# Together v2.1

You are Codex acting as the implementation partner for Together. Rebuild the pair-mode backend architecture so it is stable across iPhone, iPad, and Mac without regressing single-user behavior.

Core goals

- Replace the current pair-mode "private DB + public relay copy" design with a CloudKit single-authority shared-data architecture.
- Keep single-user data in a private data plane and pair-shared data in one authoritative shared data plane.
- Make task data, shared-space metadata, member profile data, and avatar updates use the same reliability level and lifecycle.
- Remove any dependency between pair sync lifecycle and UI mode (`activeMode`).
- Separate pair binding state, selected workspace, and shared-sync health into explicit runtime state.
- Treat SwiftData as projection/cache plus pending-mutation storage, not as a second authority.

Hard requirements

- Follow `PRODUCT_SPEC.md`, `DEVELOPMENT_GUIDELINES.md`, `DESIGN_GUIDELINES.md`, and `AGENTS.md`.
- Keep single mode as the default startup mode.
- Do not break existing single-user task flows, notifications, or profile save behavior.
- Prefer SwiftUI, SwiftData, CloudKit, and modern Swift concurrency.
- Planning comes before broad coding; update durable control-plane files as reality changes.

Deliverable

- A working pair-mode backend foundation where CloudKit shared data is the authority for pair tasks and pair metadata, local SwiftData acts as projection/cache plus mutation log, and the current relay-only pair data path is no longer required for correctness.
- Current build target:
  - milestone 05 is complete
  - milestone 06 is in progress
  - shared mutation lifecycle must now drive both remote-apply preservation and shared-sync health
  - shared-space rename flow has been split out of profile sync and must remain a first-class `.space` mutation path
  - Home task actions are being migrated off the legacy `spaceID`-only callback and onto precise `.task` shared mutation emission
  - Completed History, notification completion, and composer create flows are also being moved onto that precise shared-mutation flush path

Architecture directive

- Public DB: invite discovery only.
- Private DB: single-user data and owner-side shared zone records.
- Shared DB / CKShare: participant-side access to the same pair data authority.
- Local SwiftData: projection/cache for UI plus explicit pending mutation log.
- Avatar sync must move away from ambiguous metadata semantics and become asset/reference based within the shared authority data model.

Process requirements

1. Refresh `plans.md` before broad implementation.
2. Implement milestone by milestone.
3. Validate after each milestone.
4. Keep `documentation.md` aligned with shipped behavior.

Start now.
Do not begin broad coding until `plans.md` is coherent with this architecture.
