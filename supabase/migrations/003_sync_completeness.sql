-- supabase/migrations/003_sync_completeness.sql
-- Phase A — data correctness columns that pair sync requires

-- tasks: add local collaboration fields
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS execution_role text,
  ADD COLUMN IF NOT EXISTS response_history jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS assignment_messages jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reminder_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS location_text text,
  ADD COLUMN IF NOT EXISTS occurrence_completions jsonb;

-- spaces: support unbind semantics
ALTER TABLE spaces
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

-- project_subtasks: backfill space_id so RLS can filter
ALTER TABLE project_subtasks
  ADD COLUMN IF NOT EXISTS space_id uuid REFERENCES spaces ON DELETE CASCADE;

-- Backfill. Orphans (subtask without a project row) are deleted rather than blocking migration.
DELETE FROM project_subtasks WHERE project_id NOT IN (SELECT id FROM projects);

UPDATE project_subtasks s
SET space_id = p.space_id
FROM projects p
WHERE s.project_id = p.id AND s.space_id IS NULL;

ALTER TABLE project_subtasks ALTER COLUMN space_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_project_subtasks_space ON project_subtasks(space_id);

-- RLS tighten — subtasks enforce via space membership
DROP POLICY IF EXISTS "space members can read subtasks" ON project_subtasks;
CREATE POLICY "space members can read subtasks" ON project_subtasks
  FOR SELECT USING (is_space_member(space_id));

DROP POLICY IF EXISTS "space members can write subtasks" ON project_subtasks;
CREATE POLICY "space members can write subtasks" ON project_subtasks
  FOR ALL USING (is_space_member(space_id)) WITH CHECK (is_space_member(space_id));

-- space_members: let members exchange their local (app-side) UUID for partner identification
ALTER TABLE space_members
  ADD COLUMN IF NOT EXISTS local_user_id uuid;
