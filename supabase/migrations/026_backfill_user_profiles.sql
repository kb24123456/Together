-- 026_backfill_user_profiles.sql
--
-- 把 space_members 现存的 displayName/avatar 数据 seed 到 user_profiles。
-- 取每个 user 最新一次 updated_at 的那行作为权威值（同一个用户在多个 space
-- 理论上 nickname 应一致；如有出入以最近一次为准）。
--
-- 幂等：ON CONFLICT (user_id) DO NOTHING —— 重复执行不会覆盖已有 profile。
-- 因此可以在生产任意时刻重跑。
--
-- 限制：只回填能 join 上 auth.users 的行（防御历史脏数据；2026-04-26 校验
-- 显示生产 50 / 50 全部命中，预期不会过滤掉任何行）。

INSERT INTO public.user_profiles (
    user_id,
    display_name,
    avatar_url,
    avatar_asset_id,
    avatar_system_name,
    avatar_version,
    updated_at
)
SELECT DISTINCT ON (sm.user_id)
    sm.user_id,
    COALESCE(sm.display_name, ''),
    sm.avatar_url,
    sm.avatar_asset_id,
    sm.avatar_system_name,
    COALESCE(sm.avatar_version, 0),
    sm.updated_at
FROM public.space_members sm
JOIN auth.users au ON au.id = sm.user_id
ORDER BY sm.user_id, sm.updated_at DESC NULLS LAST
ON CONFLICT (user_id) DO NOTHING;
