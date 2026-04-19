-- Migration 016: pair-mode anniversaries (生日 / 纪念日 / 节日 / 自定义)
--
-- migrations/001 pre-created a simpler important_dates for Phase 3.
-- v2 needs a substantially different schema (kind, recurrence_rule,
-- preset holiday identity, finer notification config). No rows yet
-- and no Swift references, so drop and rebuild cleanly. CASCADE also
-- drops the old RLS policies, updated_at trigger, index, and
-- supabase_realtime publication membership — all re-created below.
DROP TABLE IF EXISTS important_dates CASCADE;

CREATE TABLE important_dates (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    space_id           uuid NOT NULL REFERENCES spaces(id) ON DELETE CASCADE,
    creator_id         uuid NOT NULL,
    kind               text NOT NULL,                 -- 'birthday' | 'anniversary' | 'holiday' | 'custom'
    title              text NOT NULL,
    date_value         date NOT NULL,                 -- 首次发生的完整公历日期
    is_recurring       boolean NOT NULL DEFAULT true,
    recurrence_rule    text,                          -- 'solar_annual' | 'lunar_annual' | null
    notify_days_before int NOT NULL DEFAULT 7,        -- 1/3/7/15/30
    notify_on_day      boolean NOT NULL DEFAULT true,
    icon               text,
    member_user_id     uuid,                          -- 仅 kind='birthday' 使用
    is_preset_holiday  boolean NOT NULL DEFAULT false,
    preset_holiday_id  text,                          -- 'valentines' | 'qixi' | 'springFestival'
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    is_deleted         boolean NOT NULL DEFAULT false,
    deleted_at         timestamptz
);

CREATE INDEX important_dates_space_idx ON important_dates (space_id, is_deleted);

-- 防止同一 space 重复勾选同一 preset
CREATE UNIQUE INDEX important_dates_unique_preset
    ON important_dates (space_id, preset_holiday_id)
    WHERE is_preset_holiday AND NOT is_deleted;

-- RLS: reuse is_space_member() helper from migration 001, matching other pair tables
ALTER TABLE important_dates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "space members can read dates" ON important_dates FOR SELECT
    USING (is_space_member(space_id));
CREATE POLICY "space members can create dates" ON important_dates FOR INSERT
    WITH CHECK (is_space_member(space_id) AND creator_id = auth.uid());
CREATE POLICY "space members can update dates" ON important_dates FOR UPDATE
    USING (is_space_member(space_id));

-- updated_at trigger (DROP CASCADE removed the prior one)
CREATE TRIGGER set_updated_at BEFORE UPDATE ON important_dates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Realtime publication membership (DROP CASCADE removed it)
ALTER PUBLICATION supabase_realtime ADD TABLE important_dates;
