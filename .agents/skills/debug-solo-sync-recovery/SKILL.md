---
name: debug-solo-sync-recovery
description: Use when Together single-mode tasks, profile, avatar, or other solo data fails to restore after reinstall, TestFlight update, device transfer, or Supabase/CloudKit sync.
---

# Debug Solo Sync Recovery

## Goal

Find the exact layer where single-mode data recovery is blocked before proposing a fix.

Do not guess CloudKit, Supabase, iCloud, or TestFlight causes from UI symptoms alone.

## Required Sequence

1. Confirm the scenario:
   - install path: update, delete-and-reinstall, or second device
   - current build number
   - device type
   - same Apple ID and same Supabase auth account
   - affected records and titles

2. Check Supabase first:
   - `device_installations` has the current build number and recent `last_seen_at`
   - target rows exist in `tasks` or other expected tables by exact id/title
   - row `space_id` matches the active single space

3. Pull the physical device container if Supabase is missing rows:
   - copy `Library/Application Support/Together/Together.store`
   - copy `Together.store-wal`
   - copy `Together.store-shm`
   - copy `Library/Preferences/com.pigdog.Together.plist`

4. Inspect local SwiftData:
   - target local rows exist
   - their `spaceID` is the canonical single space
   - `PersistentSyncChange` rows exist for those record ids
   - lifecycle is `pending`, `sending`, `failed`, or `confirmed`
   - preserve exact `lastError` text if it explains the blocked layer

5. Classify the blockage:
   - no local row: creation/persistence failed
   - local row but no outbox: mutation recording failed
   - outbox `sending`: stale send recovery or in-flight issue
   - outbox `failed`: push attempted and failed; inspect error source
   - outbox `confirmed` but Supabase missing: CloudKit acknowledgement is being mistaken for Supabase acknowledgement
   - Supabase has row but UI missing: pull/apply/UI reload path failed

6. Only then fix:
   - add a regression test that fails before the production change
   - keep Supabase as canonical backend for single-mode recovery
   - treat Supabase upsert as idempotent by record id
   - do not use global `lastPushedAt` to skip still-present local outbox rows
   - do not assume CloudKit confirmed means Supabase has the data

## Known Resolved Incident

On 2026-04-29, build 16 partially recovered single-mode tasks after reinstall:

- `测试22` reached Supabase.
- `测试11` remained local-only.
- Device SwiftData still contained both tasks.
- Outbox rows were blocked around CloudKit state, including `record to insert already exists`.
- The durable fix was in `SupabaseSoloSyncService.pushPending`: scan `pending / failed / confirmed` outbox rows for the solo space, filter confirmed rows only by whether the entity supports solo Supabase push, upsert to Supabase, then delete the outbox rows after success.

Regression tests must cover CloudKit-confirmed changes both before and after `lastPushedAt`.

## Verification

Minimum verification before declaring fixed:

- solo sync unit tests pass
- AppContext solo mutation path tests pass
- iOS simulator build passes
- physical TestFlight build uploads
- Supabase contains the test rows after opening the build
- delete-and-reinstall restores those rows to the Today UI
