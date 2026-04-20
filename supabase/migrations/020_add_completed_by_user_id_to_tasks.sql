-- Adds the authoritative "who completed this task" field to tasks.
-- Before this, CompletedHistoryView used Item.lastActionByUserID as a
-- proxy (local-only field), but that drifts whenever any post-
-- completion action (archive/unarchive, reminder) updates the row.
-- completed_by_user_id is set exactly once at completion and preserved
-- thereafter.
--
-- NULL means: this row was completed before the field existed. The
-- client falls back to lastActionByUserID (local) for display.
--
-- No backfill here — remote tasks table does not carry
-- lastActionByUserID. Clients will set completed_by_user_id on the next
-- completion action after upgrade.

ALTER TABLE public.tasks
    ADD COLUMN IF NOT EXISTS completed_by_user_id UUID;
