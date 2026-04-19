-- Migration 015: hard-delete all periodic_tasks in pair spaces.
--
-- Pair 模式 v2 不再提供例行事务功能（UX 上和家务分工差太远）。
-- Dev 阶段无线上用户，直接物理删除；solo-space 数据完全不动。
DELETE FROM periodic_tasks
WHERE space_id IN (SELECT id FROM spaces WHERE type = 'pair');
