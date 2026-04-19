-- Migration 016: pair-mode anniversaries (生日 / 纪念日 / 节日 / 自定义)
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

-- RLS（参考其他表模式，目前全局开放，匹配项目 anon-key 架构）
ALTER TABLE important_dates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "important_dates_anon_all" ON important_dates;
CREATE POLICY "important_dates_anon_all"
ON important_dates FOR ALL
TO public
USING (true)
WITH CHECK (true);
