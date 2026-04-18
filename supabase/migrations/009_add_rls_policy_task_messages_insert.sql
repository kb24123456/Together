-- =============================================================
-- Migration 009: add_rls_policy_task_messages_insert
--
-- Partner nudge feature requires clients to INSERT task_messages rows
-- of type='nudge'. Table had rowsecurity=true and a pre-existing legacy
-- INSERT policy "can create messages on accessible tasks" which gated
-- on `sender_id = auth.uid()` — same identity-mismatch trap as
-- migration 005 (client sender_id is the local app UUID, not Supabase
-- anon auth.uid()), so the legacy policy always denied.
--
-- Changes:
--   1. DROP the dead legacy INSERT policy.
--   2. CREATE a fresh INSERT policy gated only on space membership via
--      the parent task's space_id (tasks.space_id → is_space_member).
--
-- SELECT policy "can read messages of accessible tasks" is untouched —
-- it already works (only checks is_space_member). Will be useful when
-- we add message history pull in a future batch; MVP doesn't need it
-- (APNs is the nudge delivery channel, partner device doesn't pull).
-- =============================================================

DROP POLICY IF EXISTS "can create messages on accessible tasks" ON task_messages;

CREATE POLICY "space members can insert task messages" ON task_messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM tasks
      WHERE tasks.id = task_messages.task_id
        AND is_space_member(tasks.space_id)
    )
  );
