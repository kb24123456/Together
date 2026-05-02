-- 043_restrict_premium_gate_function_execute.sql
-- Tighten execute privileges for premium entitlement helpers created in 042.

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
  select (select auth.uid()) = p_user_id
    and (
      exists (
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
      )
    );
$$;

create or replace function public.has_registered_iphone_installation(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select (select auth.uid()) = p_user_id
    and exists (
      select 1
      from public.device_installations di
      where di.user_id = p_user_id
        and di.platform = 'iphone'
        and di.is_active = true
    );
$$;

revoke execute on function public.ensure_single_space(uuid, text, text) from public;
revoke execute on function public.ensure_single_space(uuid, text, text) from anon;
grant execute on function public.ensure_single_space(uuid, text, text) to authenticated;

revoke execute on function public.has_active_pro_entitlement(uuid, timestamptz) from public;
revoke execute on function public.has_active_pro_entitlement(uuid, timestamptz) from anon;
grant execute on function public.has_active_pro_entitlement(uuid, timestamptz) to authenticated;

revoke execute on function public.has_registered_iphone_installation(uuid) from public;
revoke execute on function public.has_registered_iphone_installation(uuid) from anon;
grant execute on function public.has_registered_iphone_installation(uuid) to authenticated;

revoke execute on function public.solo_sync_gate_allows(uuid, text) from public;
revoke execute on function public.solo_sync_gate_allows(uuid, text) from anon;
grant execute on function public.solo_sync_gate_allows(uuid, text) to authenticated;

revoke execute on function public.is_space_member(uuid) from public;
revoke execute on function public.is_space_member(uuid) from anon;
grant execute on function public.is_space_member(uuid) to authenticated;
