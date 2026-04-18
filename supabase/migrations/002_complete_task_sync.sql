-- =============================================================
-- Together Supabase Schema - Phase 2
-- 补全双人同步所需字段（响应历史、任务消息、催促、分配角色、位置）
-- =============================================================

-- 1. tasks 表补全同步字段
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS execution_role text DEFAULT 'initiator',
  ADD COLUMN IF NOT EXISTS assignment_state text DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS location_text text,
  ADD COLUMN IF NOT EXISTS latest_response jsonb,
  ADD COLUMN IF NOT EXISTS response_history jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS assignment_messages jsonb DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS last_action_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS last_action_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_requested_at timestamptz;

-- 2. project_subtasks 补 space_id 支持 RLS 按空间隔离
ALTER TABLE project_subtasks
  ADD COLUMN IF NOT EXISTS space_id uuid REFERENCES spaces;

-- 回填已有子任务的 space_id（从关联的 project 继承）
UPDATE project_subtasks ps
SET space_id = p.space_id
FROM projects p
WHERE ps.project_id = p.id AND ps.space_id IS NULL;

-- RLS policy 调整：允许按 space 过滤（保留原 policy 作为兼容）
DROP POLICY IF EXISTS "space members can read subtasks" ON project_subtasks;
CREATE POLICY "space members can read subtasks" ON project_subtasks
  FOR SELECT USING (
    space_id IS NULL OR is_space_member(space_id)
  );

-- 3. 过期邀请自动归档（防止 pair_invites 表堆积）
CREATE OR REPLACE FUNCTION archive_expired_invites() RETURNS void AS $$
BEGIN
  UPDATE pair_invites
  SET status = 'expired'
  WHERE status = 'pending' AND expires_at < now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. task_messages 加入 Realtime publication（支持双端评论/催促）
ALTER PUBLICATION supabase_realtime ADD TABLE task_messages;

-- 5. 空间归档（unbind）通知：为 spaces.status 更新启用 Realtime
-- （spaces 已在 001 加入 publication，此处仅确认）

-- 6. 保护性 index：加速 space 内按更新时间增量拉取
CREATE INDEX IF NOT EXISTS idx_tasks_space_updated
  ON tasks(space_id, updated_at DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_task_messages_task_created
  ON task_messages(task_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_project_subtasks_space
  ON project_subtasks(space_id) WHERE is_deleted = false;
