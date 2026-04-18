-- =============================================================
-- Migration 005: relax_creator_check_on_sync_tables
--
-- 原 INSERT policy 要求 creator_id = auth.uid()，但客户端 creator_id
-- 来自本地 app UUID（PersistentUserProfile.userID），跟 Supabase 匿名
-- auth.uid() 永远不相等 → 5 张业务表从未成功插入过任何行（v2026-04-18
-- SQL 审计确认 tasks/task_lists/projects/project_subtasks/periodic_tasks
-- 全部 count=0）。
--
-- 修复：去掉 creator_id = auth.uid() 检查，只保留 is_space_member。
-- 双人空间语义：任何成员都能创建任务；creator_id 仅作审计/显示使用。
-- =============================================================

DROP POLICY IF EXISTS "space members can create tasks" ON tasks;
CREATE POLICY "space members can create tasks" ON tasks
  FOR INSERT WITH CHECK (is_space_member(space_id));

DROP POLICY IF EXISTS "space members can create lists" ON task_lists;
CREATE POLICY "space members can create lists" ON task_lists
  FOR INSERT WITH CHECK (is_space_member(space_id));

DROP POLICY IF EXISTS "space members can create projects" ON projects;
CREATE POLICY "space members can create projects" ON projects
  FOR INSERT WITH CHECK (is_space_member(space_id));

DROP POLICY IF EXISTS "space members can create periodic" ON periodic_tasks;
CREATE POLICY "space members can create periodic" ON periodic_tasks
  FOR INSERT WITH CHECK (is_space_member(space_id));

-- project_subtasks 上有一条冗余 legacy INSERT policy（要求 creator 匹配 +
-- 项目存在性检查）。"space members can write subtasks" ALL policy 已经
-- 用 is_space_member(space_id) 全覆盖，移除 legacy 避免 permissive 分歧。
DROP POLICY IF EXISTS "can create subtasks on accessible projects" ON project_subtasks;
DROP POLICY IF EXISTS "can read subtasks of accessible projects" ON project_subtasks;
DROP POLICY IF EXISTS "can update subtasks of accessible projects" ON project_subtasks;
