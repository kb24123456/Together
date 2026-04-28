-- 029_device_installations_push_token.sql
-- Forward-safe schema patch for solo device installation push token sync.

alter table public.device_installations
add column if not exists push_token text;
