-- Add missing leading indexes for foreign keys that are queried or checked
-- during parent-row updates/deletes. Partial indexes avoid indexing NULL-only
-- optional relationships.

CREATE INDEX IF NOT EXISTS idx_pair_invites_accepted_by
ON public.pair_invites (accepted_by)
WHERE accepted_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_list_updated
ON public.tasks (list_id, updated_at DESC)
WHERE list_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_project_updated
ON public.tasks (project_id, updated_at DESC)
WHERE project_id IS NOT NULL;
