-- =============================================================
-- Migration 006: drop_creator_id_fk_on_sync_tables
--
-- 继 005 放开 RLS 后，tasks push 仍挂在 FK: tasks.creator_id REFERENCES
-- auth.users(id)。客户端 creator_id 是本地 app UUID，跟 Supabase 匿名
-- auth.users 表里的 id 永远不一致（playbook §A9 身份体系互不认识）。
--
-- 去掉 5 张业务表 creator_id 的 FK 约束，让 creator_id 成为自由审计字段。
-- 后续 batch 3 补 space_members.local_user_id 后可以换成指向
-- local_user_id 的更语义化约束。
--
-- 保留：tasks.space_id、tasks.list_id、tasks.project_id、
-- project_subtasks.project_id/space_id、spaces.owner_user_id、
-- space_members.user_id 等真正需要 referential integrity 的 FK。
-- =============================================================

ALTER TABLE tasks            DROP CONSTRAINT IF EXISTS tasks_creator_id_fkey;
ALTER TABLE task_lists       DROP CONSTRAINT IF EXISTS task_lists_creator_id_fkey;
ALTER TABLE projects         DROP CONSTRAINT IF EXISTS projects_creator_id_fkey;
ALTER TABLE project_subtasks DROP CONSTRAINT IF EXISTS project_subtasks_creator_id_fkey;
ALTER TABLE periodic_tasks   DROP CONSTRAINT IF EXISTS periodic_tasks_creator_id_fkey;
