Now implement the pair-architecture rebuild end to end.

Execution rules:

- Treat `plans.md` as the source of truth.
- Proceed milestone by milestone without unnecessary confirmation pauses.
- Prefer narrow architectural slices that replace authority paths cleanly.
- Validate after every milestone and keep docs aligned with reality.

If a bug is discovered during the rebuild:

- identify whether it is caused by legacy relay behavior, split source-of-truth, or lifecycle coupling
- fix the authority path, not the symptom
- add the smallest useful test or verification gate when practical
- record the decision in `plans.md`
- when shared-space metadata is touched, prefer `PersistentSpace` as the authority; `PersistentPairSpace` is compatibility-only and must not re-enter the runtime correctness path

Completion criteria:

- milestones are complete or explicitly descoped with rationale
- validation passes
- `documentation.md` matches shipped behavior
- pair-mode correctness no longer depends on `activeMode` or relay-only metadata transport
- relay compatibility models, if retained, are isolated to migration-only code paths
