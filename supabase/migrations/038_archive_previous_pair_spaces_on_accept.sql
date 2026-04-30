-- Archive older active pair spaces when a new pair invite is accepted.
--
-- Together supports one active pair relationship per user. Older builds only
-- archived incomplete owner-only spaces, so repeated re-pairing could leave
-- multiple two-member pair spaces active for the same devices. That made a
-- restored client attach to an old space while the partner wrote new data to
-- the latest space.

create or replace function public.accept_pair_invite(
  p_invite_id uuid,
  p_display_name text
)
returns table(
  id uuid,
  space_id uuid,
  inviter_id uuid,
  invite_code text,
  status text,
  accepted_by uuid,
  inviter_local_user_id uuid,
  inviter_display_name text,
  created_at timestamptz,
  expires_at timestamptz,
  responded_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_invite public.pair_invites%rowtype;
  v_space_status text;
begin
  if v_user_id is null then
    raise exception 'accept_pair_invite requires an authenticated user' using errcode = '42501';
  end if;

  select *
  into v_invite
  from public.pair_invites
  where pair_invites.id = p_invite_id
  for update;

  if not found then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;

  if v_invite.status <> 'pending' then
    raise exception 'invite is not pending' using errcode = '23514';
  end if;

  if v_invite.expires_at <= now() then
    update public.pair_invites
    set status = 'expired',
        responded_at = coalesce(responded_at, now())
    where pair_invites.id = p_invite_id;
    raise exception 'invite expired' using errcode = '23514';
  end if;

  if v_invite.inviter_id = v_user_id then
    raise exception 'cannot accept own invite' using errcode = '23514';
  end if;

  select spaces.status
  into v_space_status
  from public.spaces
  where spaces.id = v_invite.space_id
  for update;

  if v_space_status is distinct from 'active' then
    raise exception 'space is not active' using errcode = '23514';
  end if;

  update public.spaces s
  set status = 'archived',
      archived_at = coalesce(s.archived_at, now()),
      updated_at = now()
  where s.type = 'pair'
    and s.status = 'active'
    and s.id <> v_invite.space_id
    and exists (
      select 1
      from public.space_members sm
      where sm.space_id = s.id
        and sm.user_id in (v_invite.inviter_id, v_user_id)
    );

  update public.pair_invites
  set status = 'accepted',
      accepted_by = v_user_id,
      responded_at = now()
  where pair_invites.id = p_invite_id
  returning pair_invites.* into v_invite;

  insert into public.space_members (space_id, user_id, display_name, role)
  values (
    v_invite.space_id,
    v_user_id,
    coalesce(nullif(trim(p_display_name), ''), '我'),
    'member'
  )
  on conflict (space_id, user_id) do update
  set display_name = excluded.display_name,
      role = excluded.role,
      updated_at = now();

  return query
  select
    v_invite.id,
    v_invite.space_id,
    v_invite.inviter_id,
    v_invite.invite_code,
    v_invite.status,
    v_invite.accepted_by,
    v_invite.inviter_local_user_id,
    v_invite.inviter_display_name,
    v_invite.created_at,
    v_invite.expires_at,
    v_invite.responded_at;
end;
$$;

revoke execute on function public.accept_pair_invite(uuid, text) from anon;
revoke execute on function public.accept_pair_invite(uuid, text) from public;
grant execute on function public.accept_pair_invite(uuid, text) to authenticated;
