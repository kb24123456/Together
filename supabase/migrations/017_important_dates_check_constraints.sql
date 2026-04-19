-- Migration 017: tighten important_dates with CHECK constraints.
--
-- 016 created the table with free-form text/int columns; the Swift domain
-- model enforces closed value sets (kind, recurrence, notify_days_before,
-- is_preset_holiday/preset_holiday_id pairing). Add DB-side CHECK
-- constraints matching those enums so bad rows can't round-trip through
-- Supabase — belt and braces for the client-side validation.
ALTER TABLE important_dates
  ADD CONSTRAINT important_dates_kind_check
    CHECK (kind IN ('birthday','anniversary','holiday','custom')),
  ADD CONSTRAINT important_dates_recurrence_check
    CHECK (recurrence_rule IS NULL OR recurrence_rule IN ('solar_annual','lunar_annual')),
  ADD CONSTRAINT important_dates_notify_days_check
    CHECK (notify_days_before IN (1,3,7,15,30)),
  ADD CONSTRAINT important_dates_preset_consistency_check
    CHECK (is_preset_holiday = false OR preset_holiday_id IS NOT NULL);
