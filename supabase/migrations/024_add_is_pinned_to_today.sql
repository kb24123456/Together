-- 024_add_is_pinned_to_today.sql
-- Per spec docs/superpowers/specs/2026-04-27-anniversaries-pinned-holidays-design.md §2.1.
-- Adds the per-row pin flag that drives Today's Pinned Anniversary stack.
-- Default false so existing rows render unchanged on old client + new client.

ALTER TABLE public.important_dates
  ADD COLUMN IF NOT EXISTS is_pinned_to_today bool NOT NULL DEFAULT false;
