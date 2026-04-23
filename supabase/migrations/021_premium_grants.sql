-- Phase 2 Premium Infrastructure: white-list grants for Together Pro.
-- Coexists with RevenueCat subscriptions; PremiumGate merges both sources
-- client-side (see docs/superpowers/specs/2026-04-22-premium-infrastructure-design.md § 2.3, § 3).
--
-- Four grant categories are supported (enforced via CHECK):
--   developer   — Together team, permanent (expires_at = NULL)
--   friend      — 亲友赠送, either permanent or time-limited
--   grandfather — 老用户补偿, 通常有过期时间
--   testflight  — 公测期间覆盖
--
-- Soft-delete via revoked_at; the client query filters WHERE revoked_at IS NULL.
-- expires_at = NULL means permanent.

CREATE TABLE premium_grants (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category    text NOT NULL CHECK (category IN ('developer', 'friend', 'grandfather', 'testflight')),
    reason      text,
    granted_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz,
    revoked_at  timestamptz,
    granted_by  text,
    metadata    jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE premium_grants IS
    'White-list grants for Together Pro. Coexists with RevenueCat subscriptions; merged client-side.';
COMMENT ON COLUMN premium_grants.category IS
    'developer | friend | grandfather | testflight';
COMMENT ON COLUMN premium_grants.expires_at IS
    'NULL means permanent grant';
COMMENT ON COLUMN premium_grants.revoked_at IS
    'Soft-delete timestamp. Client queries filter WHERE revoked_at IS NULL.';

CREATE INDEX idx_premium_grants_user_id ON premium_grants(user_id);
CREATE INDEX idx_premium_grants_active
    ON premium_grants(user_id, expires_at)
    WHERE revoked_at IS NULL;

ALTER TABLE premium_grants ENABLE ROW LEVEL SECURITY;

-- SELECT: a user can only read their own grants.
-- INSERT/UPDATE/DELETE: no policy for authenticated role;
-- only service_role (Dashboard, CLI, migration scripts) can mutate.
CREATE POLICY "users_read_own_grants"
    ON premium_grants FOR SELECT
    USING (auth.uid() = user_id);
