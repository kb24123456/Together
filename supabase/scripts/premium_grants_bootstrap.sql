-- =====================================================================
-- Premium Grants Bootstrap — one-off operational SQL, NOT a migration
-- =====================================================================
-- ⚠️ 这个文件**不应该**被 `supabase db push` 执行，也不应放进 supabase/migrations/。
-- 用法：手工在 Supabase Dashboard SQL Editor 选段执行，或通过 MCP
-- execute_sql 调用。
--
-- 使用时机：
--   Section 1 (dev grants)         : 现在执行，方便团队真机调试 Pro 路径
--   Section 2 (grandfather backfill): 仅在含 Task 15 guard 的版本上线发版当天执行一次
--   Section 3 (verification)        : Section 1 / 2 执行后跑，人工核对
--
-- 相关 spec：
--   docs/superpowers/specs/2026-04-22-premium-tier-split-design.md
--   docs/superpowers/specs/2026-04-22-premium-infrastructure-design.md §3


-- =====================================================================
-- Section 1 · 创始团队 developer grants（永久）
-- =====================================================================
-- expires_at = NULL 即永久。每条 INSERT 带 `WHERE NOT EXISTS` 保证幂等，
-- 可以多次重跑不产生重复行。spec §3.3 允许同一 user_id 有多条 grants，
-- 但 developer 类没必要重复。

-- Primary founder account (357831193@qq.com)
INSERT INTO premium_grants (user_id, category, reason, granted_by, expires_at)
SELECT
    'bb7a3977-3bbc-447b-989a-3fbe6b8d8eb6'::uuid,
    'developer',
    'Together 创始团队',
    'manual-bootstrap',
    NULL
WHERE NOT EXISTS (
    SELECT 1 FROM premium_grants
    WHERE user_id = 'bb7a3977-3bbc-447b-989a-3fbe6b8d8eb6'::uuid
      AND category = 'developer'
      AND revoked_at IS NULL
);

-- Secondary test Apple ID (zxr775gqs6@privaterelay.appleid.com)
-- 如果这只是测试账号不需要永久 Pro，注释掉这段即可。
INSERT INTO premium_grants (user_id, category, reason, granted_by, expires_at)
SELECT
    '03488213-9923-4fbe-b7ef-63ee0f2571e5'::uuid,
    'developer',
    'Dev secondary Apple ID / 真机测试',
    'manual-bootstrap',
    NULL
WHERE NOT EXISTS (
    SELECT 1 FROM premium_grants
    WHERE user_id = '03488213-9923-4fbe-b7ef-63ee0f2571e5'::uuid
      AND category = 'developer'
      AND revoked_at IS NULL
);


-- =====================================================================
-- Section 2 · 现有用户 grandfather 回填（⚠️ 仅上线发版当天执行一次）
-- =====================================================================
-- 目的：Task 15 的 isPremium guard 让非 Pro 用户自动失去跨设备同步。
-- 不回填的话所有老用户 OTA 升级就丢同步——严重伤害体验。
-- expires_at = NULL 即永久感谢老用户。如果需要温和推订阅，改成
-- `now() + interval '180 days'`（14 天 grace 会在此之前介入）。
--
-- 执行前必跑这条干跑检查：
--   SELECT COUNT(*) FROM auth.users u
--   WHERE NOT EXISTS (
--     SELECT 1 FROM premium_grants pg
--     WHERE pg.user_id = u.id
--       AND pg.category IN ('grandfather', 'developer')
--       AND pg.revoked_at IS NULL
--   );
-- 数字应与"预期回填人数"一致，再取消下面 INSERT 的注释执行。

-- INSERT INTO premium_grants (user_id, category, reason, granted_by, expires_at)
-- SELECT
--     u.id,
--     'grandfather',
--     'Pre-Phase2 user, grandfathered access',
--     'launch-migration',
--     NULL
-- FROM auth.users u
-- WHERE NOT EXISTS (
--     SELECT 1 FROM premium_grants pg
--     WHERE pg.user_id = u.id
--       AND pg.category IN ('grandfather', 'developer')
--       AND pg.revoked_at IS NULL
-- );


-- =====================================================================
-- Section 3 · 验证查询（Section 1 / 2 后必跑一次）
-- =====================================================================
SELECT
    u.email,
    pg.category,
    pg.reason,
    pg.expires_at,
    pg.granted_at
FROM auth.users u
LEFT JOIN premium_grants pg ON pg.user_id = u.id AND pg.revoked_at IS NULL
ORDER BY u.created_at, pg.granted_at;
