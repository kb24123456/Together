-- =============================================================
-- Migration 004: add_deleted_at_to_project_subtasks
-- 补齐 project_subtasks 的 deleted_at 列，与其他同步表对齐。
-- pushDelete() 统一写 is_deleted + deleted_at，缺列会 PostgREST 报错。
-- =============================================================

ALTER TABLE project_subtasks
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
