-- 022_replica_identity_full.sql
-- 修 Bug 2 根因：Supabase Realtime DELETE 事件在默认 REPLICA IDENTITY 下
-- oldRecord 只包含主键，server-side filter `space_id=eq.xxx` 永远匹配不上
-- → 客户端订阅的 DELETE 事件被静默丢弃。
--
-- 影响：partner 解绑后另一方收不到 .pairMemberRemoved，本地 PairSpace
-- 永远不会切回未配对状态。
--
-- 修复：所有需要 DELETE realtime 的表设 REPLICA IDENTITY FULL，让 oldRecord
-- 包含完整行内容，filter 能正确匹配。
--
-- 副作用：WAL 体积增大（DELETE 写完整 oldRecord 而不是只主键），
-- 业务表数据量小（pair-scoped），可接受。

ALTER TABLE public.space_members      REPLICA IDENTITY FULL;
ALTER TABLE public.spaces             REPLICA IDENTITY FULL;
ALTER TABLE public.tasks              REPLICA IDENTITY FULL;
ALTER TABLE public.task_lists         REPLICA IDENTITY FULL;
ALTER TABLE public.projects           REPLICA IDENTITY FULL;
ALTER TABLE public.project_subtasks   REPLICA IDENTITY FULL;
ALTER TABLE public.periodic_tasks     REPLICA IDENTITY FULL;
ALTER TABLE public.important_dates    REPLICA IDENTITY FULL;
