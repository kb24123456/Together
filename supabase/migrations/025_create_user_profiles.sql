-- 025_create_user_profiles.sql
--
-- 引入 user-scoped profile 表：让 displayName / avatar 成为"用户自己"的属性，
-- 不再仅依附于 space_members。目标场景：
--   1. 用户在单/双人模式编辑 profile，写到 user_profiles（user-scoped）。
--   2. 删 app 重装 + SIWA 后，用 auth.uid 直接恢复 displayName + avatar。
--   3. 配对接受流程：先拿到对方 user_id 即可读 user_profiles，不再依赖 partner
--      之前是否往 space_members 同步过最新 profile。
--
-- 1.0 兼容：本 migration 仅"加表"，不动 space_members。1.0.1 客户端会
-- dual-write user_profiles + space_members；1.0 设备继续读 space_members。
-- 老字段（space_members.display_name / avatar_*）等 1.0 卸载率 >95% 后再发
-- 1.1 清理迁移 drop。
--
-- 已验证（2026-04-26 SQL）：space_members.user_id 100% = auth.uid()，因此
-- "通过 space_members JOIN 找到 partner 的 user_profiles" 这条链是直接通的，
-- 不需要先做身份桥（local_user_id 仍全部为 NULL，本次无需补齐）。

CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id            uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name       text NOT NULL DEFAULT '',
    avatar_url         text,
    avatar_asset_id    text,
    avatar_system_name text,
    avatar_version     integer NOT NULL DEFAULT 0,
    updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Realtime DELETE 事件需要完整 oldRecord 才能 server-side filter（见 022 同样原因）
ALTER TABLE public.user_profiles REPLICA IDENTITY FULL;

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 自己读写自己
DROP POLICY IF EXISTS "users read own profile" ON public.user_profiles;
CREATE POLICY "users read own profile"
    ON public.user_profiles FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users insert own profile" ON public.user_profiles;
CREATE POLICY "users insert own profile"
    ON public.user_profiles FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "users update own profile" ON public.user_profiles;
CREATE POLICY "users update own profile"
    ON public.user_profiles FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- 同 space 的成员能互读对方 profile（pair partner 配对后 first frame 用）
DROP POLICY IF EXISTS "space members read each other profiles" ON public.user_profiles;
CREATE POLICY "space members read each other profiles"
    ON public.user_profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.space_members me
            JOIN public.space_members them ON me.space_id = them.space_id
            WHERE me.user_id = auth.uid()
              AND them.user_id = public.user_profiles.user_id
        )
    );

-- updated_at 触发器（注意函数实际名是 update_updated_at，不是 set_updated_at）
DROP TRIGGER IF EXISTS set_updated_at ON public.user_profiles;
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 加入 Realtime publication，客户端订阅自己的 row（重装/多端同步）
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_profiles;
