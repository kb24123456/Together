-- =============================================================
-- Together Supabase Schema - Phase 1
-- 11 张表 + 索引 + RLS + 触发器 + Realtime
-- =============================================================

-- 1. spaces（共享空间）
CREATE TABLE spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES auth.users NOT NULL,
  type text DEFAULT 'pair',
  display_name text NOT NULL,
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. space_members（空间成员）
CREATE TABLE space_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  display_name text NOT NULL,
  avatar_url text,
  avatar_version int DEFAULT 0,
  role text DEFAULT 'member',
  joined_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(space_id, user_id)
);

-- 3. pair_invites（配对邀请）
CREATE TABLE pair_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces ON DELETE CASCADE NOT NULL,
  inviter_id uuid REFERENCES auth.users NOT NULL,
  invite_code text NOT NULL,
  status text DEFAULT 'pending',
  accepted_by uuid REFERENCES auth.users,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '24 hours'),
  responded_at timestamptz
);

-- 4. task_lists（列表）
CREATE TABLE task_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  kind text DEFAULT 'custom',
  color_token text,
  sort_order float8 DEFAULT 0,
  is_archived bool DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 5. projects（项目）
CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  name text NOT NULL,
  notes text,
  color_token text,
  status text DEFAULT 'active',
  target_date timestamptz,
  remind_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 6. tasks（任务）
CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  list_id uuid REFERENCES task_lists,
  project_id uuid REFERENCES projects,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  assignee_mode text DEFAULT 'self',
  status text DEFAULT 'pending',
  due_at timestamptz,
  has_explicit_time bool DEFAULT false,
  remind_at timestamptz,
  is_pinned bool DEFAULT false,
  is_draft bool DEFAULT false,
  is_read_by_partner bool DEFAULT false,
  read_at timestamptz,
  repeat_rule jsonb,
  occurrence_completions jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  is_archived bool DEFAULT false,
  archived_at timestamptz,
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 7. task_messages（任务消息流）
CREATE TABLE task_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid REFERENCES tasks ON DELETE CASCADE NOT NULL,
  sender_id uuid REFERENCES auth.users NOT NULL,
  type text NOT NULL,
  content text,
  emoji text,
  rps_result jsonb,
  created_at timestamptz DEFAULT now()
);

-- 8. project_subtasks（项目子任务）
CREATE TABLE project_subtasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES projects ON DELETE CASCADE NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  is_completed bool DEFAULT false,
  sort_order int DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false
);

-- 9. periodic_tasks（例行事务）
CREATE TABLE periodic_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  notes text,
  cycle text NOT NULL,
  reminder_rules jsonb DEFAULT '[]',
  completions jsonb DEFAULT '{}',
  sort_order float8 DEFAULT 0,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false,
  deleted_at timestamptz
);

-- 10. important_dates（纪念日）— Phase 3 使用，提前建表
CREATE TABLE important_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  space_id uuid REFERENCES spaces NOT NULL,
  creator_id uuid REFERENCES auth.users NOT NULL,
  title text NOT NULL,
  date date NOT NULL,
  is_recurring bool DEFAULT true,
  remind_days_before int,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  is_deleted bool DEFAULT false
);

-- 11. device_tokens（APNs 推送令牌）
CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users NOT NULL,
  token text NOT NULL,
  platform text DEFAULT 'ios',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, token)
);

-- =============================================================
-- 索引
-- =============================================================

CREATE INDEX idx_space_members_user ON space_members(user_id);
CREATE INDEX idx_space_members_space ON space_members(space_id);
CREATE INDEX idx_tasks_space ON tasks(space_id);
CREATE INDEX idx_tasks_space_active ON tasks(space_id, is_archived) WHERE is_deleted = false;
CREATE INDEX idx_task_lists_space ON task_lists(space_id) WHERE is_deleted = false;
CREATE INDEX idx_projects_space ON projects(space_id) WHERE is_deleted = false;
CREATE INDEX idx_periodic_tasks_space ON periodic_tasks(space_id) WHERE is_deleted = false;
CREATE INDEX idx_important_dates_space ON important_dates(space_id) WHERE is_deleted = false;
CREATE INDEX idx_task_messages_task ON task_messages(task_id, created_at DESC);
CREATE INDEX idx_pair_invites_code ON pair_invites(invite_code) WHERE status = 'pending';
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX idx_project_subtasks_project ON project_subtasks(project_id) WHERE is_deleted = false;

-- =============================================================
-- RLS 辅助函数
-- =============================================================

CREATE OR REPLACE FUNCTION is_space_member(check_space_id uuid)
RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.space_members
    WHERE space_id = check_space_id
    AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public;

-- =============================================================
-- RLS 策略
-- =============================================================

-- spaces
ALTER TABLE spaces ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read spaces" ON spaces FOR SELECT USING (is_space_member(id));
CREATE POLICY "authenticated can create spaces" ON spaces FOR INSERT WITH CHECK (owner_user_id = auth.uid());
CREATE POLICY "owner can update space" ON spaces FOR UPDATE USING (owner_user_id = auth.uid());

-- space_members
ALTER TABLE space_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read members" ON space_members FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can insert members" ON space_members FOR INSERT WITH CHECK (is_space_member(space_id) OR user_id = auth.uid());
CREATE POLICY "members can update own profile" ON space_members FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "space members can delete members" ON space_members FOR DELETE USING (is_space_member(space_id));

-- pair_invites
ALTER TABLE pair_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "inviter can read own invites" ON pair_invites FOR SELECT USING (inviter_id = auth.uid());
CREATE POLICY "anyone can lookup pending invite" ON pair_invites FOR SELECT USING (status = 'pending' AND expires_at > now());
CREATE POLICY "authenticated can create invite" ON pair_invites FOR INSERT WITH CHECK (inviter_id = auth.uid());
CREATE POLICY "anyone can accept pending invite" ON pair_invites FOR UPDATE USING (status = 'pending' AND expires_at > now());

-- tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read tasks" ON tasks FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create tasks" ON tasks FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update tasks" ON tasks FOR UPDATE USING (is_space_member(space_id));

-- task_messages
ALTER TABLE task_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "can read messages of accessible tasks" ON task_messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_messages.task_id AND is_space_member(tasks.space_id)));
CREATE POLICY "can create messages on accessible tasks" ON task_messages FOR INSERT
  WITH CHECK (sender_id = auth.uid() AND EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_messages.task_id AND is_space_member(tasks.space_id)));

-- task_lists
ALTER TABLE task_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read lists" ON task_lists FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create lists" ON task_lists FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update lists" ON task_lists FOR UPDATE USING (is_space_member(space_id));

-- projects
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read projects" ON projects FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create projects" ON projects FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update projects" ON projects FOR UPDATE USING (is_space_member(space_id));

-- project_subtasks
ALTER TABLE project_subtasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "can read subtasks of accessible projects" ON project_subtasks FOR SELECT
  USING (EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));
CREATE POLICY "can create subtasks on accessible projects" ON project_subtasks FOR INSERT
  WITH CHECK (creator_id = auth.uid() AND EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));
CREATE POLICY "can update subtasks of accessible projects" ON project_subtasks FOR UPDATE
  USING (EXISTS (SELECT 1 FROM projects WHERE projects.id = project_subtasks.project_id AND is_space_member(projects.space_id)));

-- periodic_tasks
ALTER TABLE periodic_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read periodic" ON periodic_tasks FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create periodic" ON periodic_tasks FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update periodic" ON periodic_tasks FOR UPDATE USING (is_space_member(space_id));

-- important_dates
ALTER TABLE important_dates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "space members can read dates" ON important_dates FOR SELECT USING (is_space_member(space_id));
CREATE POLICY "space members can create dates" ON important_dates FOR INSERT WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update dates" ON important_dates FOR UPDATE USING (is_space_member(space_id));

-- device_tokens
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users manage own tokens" ON device_tokens FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "users create own tokens" ON device_tokens FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users update own tokens" ON device_tokens FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "users delete own tokens" ON device_tokens FOR DELETE USING (user_id = auth.uid());

-- =============================================================
-- updated_at 自动更新触发器
-- =============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON spaces FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON space_members FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON task_lists FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON periodic_tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON important_dates FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON device_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- Realtime 启用
-- =============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE spaces;
ALTER PUBLICATION supabase_realtime ADD TABLE space_members;
ALTER PUBLICATION supabase_realtime ADD TABLE tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE task_lists;
ALTER PUBLICATION supabase_realtime ADD TABLE projects;
ALTER PUBLICATION supabase_realtime ADD TABLE project_subtasks;
ALTER PUBLICATION supabase_realtime ADD TABLE periodic_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE task_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE important_dates;
