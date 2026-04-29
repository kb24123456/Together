-- 031_harden_pairing_storage_rls.sql
-- Production hardening for pairing, push tokens, profile rows, and avatar storage.
--
-- Goals:
-- 1. Pair invite acceptance is atomic: accept invite + insert membership in one RPC.
-- 2. Users can no longer self-insert into arbitrary spaces by knowing a space UUID.
-- 3. Avatar storage is restricted to authenticated users and their own path.
-- 4. Incremental sync queries have composite indexes on (space_id, updated_at).

-- Existing expired pending invites block a unique active-pending code index.
update public.pair_invites
set status = 'expired',
    responded_at = coalesce(responded_at, now())
where status = 'pending'
  and expires_at < now();

create or replace function public.expire_pair_invites_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.pair_invites
  set status = 'expired',
      responded_at = coalesce(responded_at, now())
  where status = 'pending'
    and expires_at < now();

  return null;
end;
$$;

drop trigger if exists expire_pair_invites_before_insert on public.pair_invites;
create trigger expire_pair_invites_before_insert
before insert on public.pair_invites
for each statement
execute function public.expire_pair_invites_before_insert();

create unique index if not exists idx_pair_invites_pending_code_unique
on public.pair_invites(invite_code)
where status = 'pending';

create index if not exists idx_pair_invites_space_created
on public.pair_invites(space_id, created_at desc);

create index if not exists idx_pair_invites_inviter_status
on public.pair_invites(inviter_id, status, created_at desc);

create index if not exists idx_tasks_space_updated_all
on public.tasks(space_id, updated_at desc);

create index if not exists idx_task_lists_space_updated
on public.task_lists(space_id, updated_at desc);

create index if not exists idx_projects_space_updated
on public.projects(space_id, updated_at desc);

create index if not exists idx_project_subtasks_space_updated
on public.project_subtasks(space_id, updated_at desc);

create index if not exists idx_periodic_tasks_space_updated
on public.periodic_tasks(space_id, updated_at desc);

create index if not exists idx_important_dates_space_updated
on public.important_dates(space_id, updated_at desc);

create index if not exists idx_space_members_space_updated
on public.space_members(space_id, updated_at desc);

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

revoke execute on function public.accept_pair_invite(uuid, text) from public;
grant execute on function public.accept_pair_invite(uuid, text) to authenticated;

drop policy if exists "anyone can accept pending invite" on public.pair_invites;
drop policy if exists "inviter can update own pending invites" on public.pair_invites;
create policy "inviter can update own pending invites"
on public.pair_invites
for update
to authenticated
using (
  inviter_id = (select auth.uid())
  and status = 'pending'
)
with check (
  inviter_id = (select auth.uid())
  and status in ('pending', 'cancelled', 'expired')
);

drop policy if exists "inviter can read own invites" on public.pair_invites;
create policy "inviter can read own invites"
on public.pair_invites
for select
to authenticated
using (inviter_id = (select auth.uid()));

drop policy if exists "acceptor can read accepted invites" on public.pair_invites;
create policy "acceptor can read accepted invites"
on public.pair_invites
for select
to authenticated
using (accepted_by = (select auth.uid()));

drop policy if exists "anyone can lookup pending invite" on public.pair_invites;
create policy "anyone can lookup pending invite"
on public.pair_invites
for select
to authenticated
using (status = 'pending' and expires_at > now());

drop policy if exists "authenticated can create invite" on public.pair_invites;
create policy "authenticated can create invite"
on public.pair_invites
for insert
to authenticated
with check (inviter_id = (select auth.uid()));

drop policy if exists "space members can insert members" on public.space_members;
create policy "space owners can insert their own member row"
on public.space_members
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.spaces s
    where s.id = space_members.space_id
      and s.owner_user_id = (select auth.uid())
  )
);

drop policy if exists "members can update own profile" on public.space_members;
create policy "members can update own profile"
on public.space_members
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "space members can delete members" on public.space_members;
create policy "members can delete own member row"
on public.space_members
for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "space members can read members" on public.space_members;
create policy "space members can read members"
on public.space_members
for select
to authenticated
using (is_space_member(space_id));

drop policy if exists "users manage own tokens" on public.device_tokens;
drop policy if exists "users create own tokens" on public.device_tokens;
drop policy if exists "users update own tokens" on public.device_tokens;
drop policy if exists "users delete own tokens" on public.device_tokens;

create policy "users manage own tokens"
on public.device_tokens
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "users create own tokens"
on public.device_tokens
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "users update own tokens"
on public.device_tokens
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "users delete own tokens"
on public.device_tokens
for delete
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "users_read_own_grants" on public.premium_grants;
create policy "users_read_own_grants"
on public.premium_grants
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "users read own profile" on public.user_profiles;
create policy "users read own profile"
on public.user_profiles
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "users insert own profile" on public.user_profiles;
create policy "users insert own profile"
on public.user_profiles
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "users update own profile" on public.user_profiles;
create policy "users update own profile"
on public.user_profiles
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "space members read each other profiles" on public.user_profiles;
create policy "space members read each other profiles"
on public.user_profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.space_members me
    join public.space_members them on them.space_id = me.space_id
    where me.user_id = (select auth.uid())
      and them.user_id = user_profiles.user_id
  )
);

drop policy if exists "avatars_public_bucket_select" on storage.buckets;
create policy "avatars_authenticated_bucket_select"
on storage.buckets
for select
to authenticated
using (id = 'avatars');

drop policy if exists "avatars_public_insert" on storage.objects;
drop policy if exists "avatars_public_update" on storage.objects;
drop policy if exists "avatars_public_select" on storage.objects;

create policy "avatars_authenticated_select_own_path"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
    or (
      (storage.foldername(name))[1] <> 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
  )
);

create policy "avatars_authenticated_insert_own_path"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
    or (
      (storage.foldername(name))[1] <> 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
  )
);

create policy "avatars_authenticated_update_own_path"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
    or (
      (storage.foldername(name))[1] <> 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
  )
)
with check (
  bucket_id = 'avatars'
  and (
    (
      (storage.foldername(name))[1] = 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
    or (
      (storage.foldername(name))[1] <> 'users'
      and (storage.foldername(name))[2] = (select auth.uid())::text
    )
  )
);

update storage.buckets
set file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg']
where id = 'avatars';
