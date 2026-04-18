-- =============================================================
-- Migration 008: add_assignment_state_to_tasks
--
-- Plan A 双人协作字段加了 execution_role/response_history/
-- assignment_messages 但漏了 assignment_state。iPad 接受/拒绝
-- partner task 时本地 assignmentState 变化，但 DTO 不带这字段也没
-- 对应列，服务端永远记录不下来 → iPhone catchUp 收到 TaskDTO 也没
-- assignment_state 字段，applyToLocal 不动本地 state → iPhone 一直
-- 显示"待对方回应"。
-- =============================================================

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assignment_state text NOT NULL DEFAULT 'active';
