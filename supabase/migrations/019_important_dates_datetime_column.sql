-- Migration 019: change important_dates.date_value from date to timestamptz
--
-- PostgREST returns `date` columns as bare "YYYY-MM-DD" strings, which
-- Swift's JSONDecoder cannot decode into Date with any of its default
-- strategies. iPhone push worked (ISO8601 → date cast on write), but iPad
-- pull kept failing with "The data couldn't be read because it isn't in the
-- correct format." on every CatchUp cycle.
--
-- Aligning with tasks / projects / periodic_tasks, which store dates as
-- timestamptz, lets the Supabase Swift SDK's built-in ISO8601 handling
-- work both directions. Existing rows cast cleanly (PG turns "1999-01-11"
-- into "1999-01-11 00:00:00+00"). UI layer extracts year/month/day via
-- Calendar(.current) so the timezone is irrelevant for display.
ALTER TABLE important_dates
    ALTER COLUMN date_value TYPE timestamptz
    USING date_value::timestamptz;
