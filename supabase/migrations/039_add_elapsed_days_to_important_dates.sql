-- Migration 039: per-important-date elapsed-days display preference.
--
-- Existing anniversary rows keep the behavior users already expect from the
-- "我们在一起的日子" capsule. Custom rows and all new rows default off.

alter table public.important_dates
add column if not exists shows_elapsed_days boolean not null default false;

update public.important_dates
set shows_elapsed_days = true
where kind = 'anniversary'
  and is_deleted = false;
