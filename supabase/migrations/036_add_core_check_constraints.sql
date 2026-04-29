-- Mirror app enum boundaries in the database so production data cannot drift
-- into values the Swift client cannot decode meaningfully.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_spaces_type' AND conrelid = 'public.spaces'::regclass) THEN
    ALTER TABLE public.spaces
      ADD CONSTRAINT ck_spaces_type CHECK (type IN ('single', 'pair', 'multi')) NOT VALID;
    ALTER TABLE public.spaces VALIDATE CONSTRAINT ck_spaces_type;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_spaces_status' AND conrelid = 'public.spaces'::regclass) THEN
    ALTER TABLE public.spaces
      ADD CONSTRAINT ck_spaces_status CHECK (status IN ('active', 'paused', 'archived')) NOT VALID;
    ALTER TABLE public.spaces VALIDATE CONSTRAINT ck_spaces_status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_pair_invites_status' AND conrelid = 'public.pair_invites'::regclass) THEN
    ALTER TABLE public.pair_invites
      ADD CONSTRAINT ck_pair_invites_status CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled', 'revoked')) NOT VALID;
    ALTER TABLE public.pair_invites VALIDATE CONSTRAINT ck_pair_invites_status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_pair_invites_code_format' AND conrelid = 'public.pair_invites'::regclass) THEN
    ALTER TABLE public.pair_invites
      ADD CONSTRAINT ck_pair_invites_code_format CHECK (invite_code ~ '^[0-9]{6}$') NOT VALID;
    ALTER TABLE public.pair_invites VALIDATE CONSTRAINT ck_pair_invites_code_format;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_space_members_role' AND conrelid = 'public.space_members'::regclass) THEN
    ALTER TABLE public.space_members
      ADD CONSTRAINT ck_space_members_role CHECK (role IN ('owner', 'member')) NOT VALID;
    ALTER TABLE public.space_members VALIDATE CONSTRAINT ck_space_members_role;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_task_lists_kind' AND conrelid = 'public.task_lists'::regclass) THEN
    ALTER TABLE public.task_lists
      ADD CONSTRAINT ck_task_lists_kind CHECK (kind IN ('systemInbox', 'systemToday', 'systemUpcoming', 'custom')) NOT VALID;
    ALTER TABLE public.task_lists VALIDATE CONSTRAINT ck_task_lists_kind;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tasks_status' AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT ck_tasks_status CHECK (status IN ('pendingConfirmation', 'inProgress', 'completed', 'declinedOrBlocked')) NOT VALID;
    ALTER TABLE public.tasks VALIDATE CONSTRAINT ck_tasks_status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tasks_assignee_mode' AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT ck_tasks_assignee_mode CHECK (assignee_mode IN ('self', 'partner', 'both')) NOT VALID;
    ALTER TABLE public.tasks VALIDATE CONSTRAINT ck_tasks_assignee_mode;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tasks_assignment_state' AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT ck_tasks_assignment_state CHECK (assignment_state IN ('pendingResponse', 'accepted', 'snoozed', 'declined', 'active', 'completed')) NOT VALID;
    ALTER TABLE public.tasks VALIDATE CONSTRAINT ck_tasks_assignment_state;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_tasks_execution_role' AND conrelid = 'public.tasks'::regclass) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT ck_tasks_execution_role CHECK (execution_role IS NULL OR execution_role IN ('initiator', 'recipient', 'both')) NOT VALID;
    ALTER TABLE public.tasks VALIDATE CONSTRAINT ck_tasks_execution_role;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_projects_status' AND conrelid = 'public.projects'::regclass) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT ck_projects_status CHECK (status IN ('active', 'onHold', 'completed', 'archived')) NOT VALID;
    ALTER TABLE public.projects VALIDATE CONSTRAINT ck_projects_status;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_periodic_tasks_cycle' AND conrelid = 'public.periodic_tasks'::regclass) THEN
    ALTER TABLE public.periodic_tasks
      ADD CONSTRAINT ck_periodic_tasks_cycle CHECK (cycle IN ('weekly', 'monthly', 'quarterly', 'yearly')) NOT VALID;
    ALTER TABLE public.periodic_tasks VALIDATE CONSTRAINT ck_periodic_tasks_cycle;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_task_messages_type' AND conrelid = 'public.task_messages'::regclass) THEN
    ALTER TABLE public.task_messages
      ADD CONSTRAINT ck_task_messages_type CHECK (type IN ('nudge', 'comment', 'rps_result')) NOT VALID;
    ALTER TABLE public.task_messages VALIDATE CONSTRAINT ck_task_messages_type;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_device_tokens_platform' AND conrelid = 'public.device_tokens'::regclass) THEN
    ALTER TABLE public.device_tokens
      ADD CONSTRAINT ck_device_tokens_platform CHECK (platform IN ('ios', 'ipados', 'macos')) NOT VALID;
    ALTER TABLE public.device_tokens VALIDATE CONSTRAINT ck_device_tokens_platform;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_device_tokens_hex' AND conrelid = 'public.device_tokens'::regclass) THEN
    ALTER TABLE public.device_tokens
      ADD CONSTRAINT ck_device_tokens_hex CHECK (token ~ '^[0-9a-f]+$') NOT VALID;
    ALTER TABLE public.device_tokens VALIDATE CONSTRAINT ck_device_tokens_hex;
  END IF;
END $$;
