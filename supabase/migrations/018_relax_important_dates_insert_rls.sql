-- Migration 018: relax important_dates INSERT RLS to match other pair tables.
--
-- 016 accidentally wrote a stricter policy than tasks/projects/periodic_tasks:
--   WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid())
--
-- The project's id model has two separate user_id universes (local UUID vs
-- Supabase auth.uid()), so the extra `creator_id = auth.uid()` check made
-- every INSERT fail under the anon-key push path. Other pair tables only
-- guard on `is_space_member(space_id)`; align important_dates with them.
DROP POLICY IF EXISTS "space members can create dates" ON important_dates;
CREATE POLICY "space members can create dates" ON important_dates FOR INSERT
    WITH CHECK (is_space_member(space_id));
