-- Trigger functions are implementation details, not client-callable RPCs.
-- Existing triggers continue to execute them; clients should not have direct
-- EXECUTE permission on these SECURITY DEFINER functions.

REVOKE EXECUTE ON FUNCTION public.notify_push_on_change() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_push_on_change() FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_push_on_change() FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.expire_pair_invites_before_insert() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_pair_invites_before_insert() FROM anon;
REVOKE EXECUTE ON FUNCTION public.expire_pair_invites_before_insert() FROM authenticated;

GRANT EXECUTE ON FUNCTION public.notify_push_on_change() TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_pair_invites_before_insert() TO service_role;
