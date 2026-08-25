---
status: accepted
---

# Use append-only events for todo lifecycle history

## Context

Together needs to explain how a todo moved from creation to completion, including postponements, schedule drift and reopening. Storing only mutable counters on `PersistentItem` would discard the evidence needed to recalculate definitions and could lose increments when SwiftData records merge through CloudKit. A full activity log would collect unrelated UI behavior and exceed the product goal.

## Decision

Keep the existing task record as the canonical current state and store planning-relevant history as separate append-only lifecycle events. Write the task mutation and its event in the same local database transaction. Derive postpone counts, cumulative delay, schedule drift, reopen counts and review timelines from effective events; any summary cache is rebuildable and never authoritative.

The event boundary is limited to committed domain facts: creation, first scheduling, postponing, moving earlier, clearing a schedule, rescheduling after a clear, completing and reopening. It excludes UI source, text edits, reminder-only changes and draft interactions. App, notification, Widget and Live Activity completion paths must produce the same semantic event.

## Consequences

- CloudKit merges independent event records instead of competing mutable counters, preserving more evidence for deterministic replay.
- Repository and Widget writes become stricter: partial success is not allowed, and schema mismatch must fail closed.
- Reads require stable ordering, deduplication and lifecycle replay; storage grows with meaningful task changes.
- Legacy tasks without a creation event remain explicitly incomplete rather than receiving fabricated history.
- Permanent task deletion must explicitly remove companion events because CloudKit-compatible models do not rely on a required cascade relationship.

## Alternatives considered

- Mutable counters and first / last timestamp fields on the task: simpler reads, but lossy, harder to redefine and vulnerable to merge conflicts.
- A general audit or analytics log: more flexible, but records irrelevant UI behavior and creates unnecessary privacy and retention costs.
- Reconstructing history from the current task record: impossible for past due-date changes and reopen cycles.
