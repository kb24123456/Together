-- 027_solo_recovery.sql
-- Solo recovery foundation: one active single space per owner and device registry.

do $$
begin
  if exists (
    select owner_user_id
    from public.spaces
    where type = 'single' and status = 'active'
    group by owner_user_id
    having count(*) > 1
  ) then
    raise exception 'duplicate active single spaces exist; archive or merge them before applying 027_solo_recovery';
  end if;
end $$;

create unique index if not exists idx_spaces_one_active_single_per_owner
on public.spaces(owner_user_id)
where type = 'single' and status = 'active';

create table if not exists public.device_installations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  platform text not null check (platform in ('iphone', 'ipad', 'mac')),
  device_name text,
  app_version text,
  build_number text,
  is_active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_sync_at timestamptz,
  unique(user_id, installation_id)
);

create index if not exists idx_device_installations_user
on public.device_installations(user_id);

alter table public.device_installations enable row level security;

drop policy if exists "users can read own device installations" on public.device_installations;
create policy "users can read own device installations"
on public.device_installations
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "users can insert own device installations" on public.device_installations;
create policy "users can insert own device installations"
on public.device_installations
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "users can update own device installations" on public.device_installations;
create policy "users can update own device installations"
on public.device_installations
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
