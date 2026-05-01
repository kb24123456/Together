-- Migration 041: task message comment constraints
--
-- Chat comments now use task_messages(type='comment', content=...).
-- The app enforces these checks client-side too, but the database remains
-- the final guard against empty comments, oversized comments, and comments on
-- completed/deleted tasks.

ALTER TABLE public.task_messages
  DROP CONSTRAINT IF EXISTS ck_task_messages_comment_content;

ALTER TABLE public.task_messages
  ADD CONSTRAINT ck_task_messages_comment_content CHECK (
    type <> 'comment'
    OR (
      content IS NOT NULL
      AND length(regexp_replace(content, '^[[:space:]]+|[[:space:]]+$', '', 'g')) BETWEEN 1 AND 500
    )
  ) NOT VALID;

ALTER TABLE public.task_messages
  VALIDATE CONSTRAINT ck_task_messages_comment_content;

DROP POLICY IF EXISTS "space members can insert task messages" ON public.task_messages;

CREATE POLICY "space members can insert task messages" ON public.task_messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.tasks
      WHERE tasks.id = task_messages.task_id
        AND is_space_member(tasks.space_id)
        AND (
          task_messages.type <> 'comment'
          OR (
            tasks.status IS DISTINCT FROM 'completed'
            AND coalesce(tasks.is_deleted, false) = false
          )
        )
    )
  );
