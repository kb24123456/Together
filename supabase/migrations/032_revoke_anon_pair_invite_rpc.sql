-- 032_revoke_anon_pair_invite_rpc.sql
-- Defense-in-depth: accept_pair_invite still checks auth.uid(), but anon should
-- not have EXECUTE on this mutation RPC at all.

revoke execute on function public.accept_pair_invite(uuid, text) from anon;
revoke execute on function public.accept_pair_invite(uuid, text) from public;
grant execute on function public.accept_pair_invite(uuid, text) to authenticated;

revoke execute on function public.expire_pair_invites_before_insert() from anon;
revoke execute on function public.expire_pair_invites_before_insert() from public;
