-- 042_premium_entitlements_and_solo_sync_gate.sql
-- Server-side premium source for RevenueCat webhook events, plus a solo-sync gate
-- that no longer relies only on a client-provided isPro boolean.

create table if not exists public.premium_entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null default 'revenuecat' check (provider in ('revenuecat')),
  entitlement_id text not null,
  product_id text,
  original_transaction_id text,
  transaction_id text,
  store text,
  environment text,
  purchased_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  last_event_type text,
  last_event_at timestamptz not null default now(),
  raw_event jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider, user_id, entitlement_id)
);

create index if not exists idx_premium_entitlements_user_active
on public.premium_entitlements(user_id, entitlement_id, expires_at)
where revoked_at is null;

alter table public.premium_entitlements enable row level security;

drop policy if exists "users can read own premium entitlements" on public.premium_entitlements;
create policy "users can read own premium entitlements"
on public.premium_entitlements
for select
to authenticated
using ((select auth.uid()) = user_id);

drop trigger if exists set_updated_at on public.premium_entitlements;
create trigger set_updated_at
before update on public.premium_entitlements
for each row execute function update_updated_at();

create or replace function public.has_active_pro_entitlement(
  p_user_id uuid,
  p_now timestamptz default now()
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.premium_grants pg
    where pg.user_id = p_user_id
      and pg.revoked_at is null
      and (pg.expires_at is null or pg.expires_at > p_now)
  )
  or exists (
    select 1
    from public.premium_entitlements pe
    where pe.user_id = p_user_id
      and pe.entitlement_id = 'pro'
      and pe.revoked_at is null
      and (pe.expires_at is null or pe.expires_at > p_now)
  );
$$;

revoke execute on function public.has_active_pro_entitlement(uuid, timestamptz) from public;
grant execute on function public.has_active_pro_entitlement(uuid, timestamptz) to authenticated;

create or replace function public.has_registered_iphone_installation(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.device_installations di
    where di.user_id = p_user_id
      and di.platform = 'iphone'
      and di.is_active = true
  );
$$;

revoke execute on function public.has_registered_iphone_installation(uuid) from public;
grant execute on function public.has_registered_iphone_installation(uuid) to authenticated;

create or replace function public.solo_sync_gate_allows(
  p_user_id uuid,
  p_platform text
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select (select auth.uid()) = p_user_id
     and p_platform in ('iphone', 'ipad', 'mac')
     and (
       p_platform = 'iphone'
       or public.has_active_pro_entitlement(p_user_id)
     );
$$;

revoke execute on function public.solo_sync_gate_allows(uuid, text) from public;
grant execute on function public.solo_sync_gate_allows(uuid, text) to authenticated;

-- Tighten the shared helper used by solo tables. Pair spaces keep the existing
-- member-based access; single spaces additionally require active Pro or an
-- already registered iPhone installation. The iPhone exception preserves the
-- product-approved "second iPhone restore" path.
create or replace function public.is_space_member(check_space_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.space_members sm
    join public.spaces s on s.id = sm.space_id
    where sm.space_id = check_space_id
      and sm.user_id = (select auth.uid())
      and (
        s.type <> 'single'
        or public.has_active_pro_entitlement(sm.user_id)
        or public.has_registered_iphone_installation(sm.user_id)
      )
  );
$$;

drop policy if exists "users can insert own device installations" on public.device_installations;
create policy "users can insert own device installations"
on public.device_installations
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.solo_sync_gate_allows(user_id, platform)
);

drop policy if exists "users can update own device installations" on public.device_installations;
create policy "users can update own device installations"
on public.device_installations
for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.solo_sync_gate_allows(user_id, platform)
);

drop function if exists public.ensure_single_space(uuid, text);

create or replace function public.ensure_single_space(
  p_user_id uuid,
  p_display_name text,
  p_platform text default 'iphone'
)
returns table(id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_space_id uuid;
begin
  if (select auth.uid()) is null or (select auth.uid()) <> p_user_id then
    raise exception 'ensure_single_space user mismatch' using errcode = '42501';
  end if;

  if p_platform not in ('iphone', 'ipad', 'mac') then
    raise exception 'unsupported solo sync platform' using errcode = '23514';
  end if;

  if not public.solo_sync_gate_allows(p_user_id, p_platform) then
    raise exception 'solo sync requires active Pro entitlement' using errcode = '42501';
  end if;

  insert into public.spaces as inserted_space (owner_user_id, type, display_name, status)
  values (p_user_id, 'single', p_display_name, 'active')
  on conflict (owner_user_id) where type = 'single' and status = 'active'
  do nothing
  returning inserted_space.id into v_space_id;

  if v_space_id is null then
    select s.id
    into v_space_id
    from public.spaces s
    where s.owner_user_id = p_user_id
      and s.type = 'single'
      and s.status = 'active'
    order by s.updated_at desc
    limit 1;
  end if;

  if v_space_id is null then
    raise exception 'ensure_single_space failed to find or create a space' using errcode = '23514';
  end if;

  insert into public.space_members (space_id, user_id, display_name, role)
  values (v_space_id, p_user_id, '我', 'owner')
  on conflict (space_id, user_id) do update
  set display_name = excluded.display_name,
      role = 'owner',
      updated_at = now();

  return query select v_space_id as id;
end;
$$;

revoke execute on function public.ensure_single_space(uuid, text, text) from public;
grant execute on function public.ensure_single_space(uuid, text, text) to authenticated;
