-- 028_ensure_single_space_rpc.sql
-- Restore/find an owner's active single space even if its owner membership row is missing.

create or replace function public.ensure_single_space(
  p_user_id uuid,
  p_display_name text
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

grant execute on function public.ensure_single_space(uuid, text) to authenticated;
