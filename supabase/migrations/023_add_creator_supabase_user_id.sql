-- 023_add_creator_supabase_user_id.sql
-- 修 D3: push notification 自己给自己发。
--
-- 根因：客户端 push tasks 时 creator_id = 本地 User.id（不是 Supabase auth.uid）。
-- send-push-notification edge function 没法用 creator_id 跟 device_tokens.user_id
-- (=auth.uid) 直接 join 过滤 sender，于是 fan-out 给 space 所有 member 的所有
-- token，依赖客户端 willPresent filter 排除自己。但 willPresent 仅前台触发，
-- 锁屏/后台时通知直接显示，filter 失效。
--
-- 修法：tasks/task_messages 加 nullable `creator_supabase_user_id` 字段（auth.uid），
-- 客户端 push 时同时写入。edge function 用此字段直接 server-side 过滤掉 sender。
-- nullable 兼容老 client 写入的 row，老 row 走旧 fan-out 路径（仍依赖客户端 filter）。

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS creator_supabase_user_id uuid REFERENCES auth.users;

ALTER TABLE public.task_messages
  ADD COLUMN IF NOT EXISTS sender_supabase_user_id uuid REFERENCES auth.users;

CREATE INDEX IF NOT EXISTS idx_tasks_creator_sb_uid ON public.tasks(creator_supabase_user_id);
CREATE INDEX IF NOT EXISTS idx_task_messages_sender_sb_uid ON public.task_messages(sender_supabase_user_id);
