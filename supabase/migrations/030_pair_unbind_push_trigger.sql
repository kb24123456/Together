-- Notify the remaining partner when one member leaves a pair space.
-- The existing notify_push_on_change() function forwards row changes to the
-- send-push-notification Edge Function.

DROP TRIGGER IF EXISTS push_on_space_member_delete ON public.space_members;

CREATE TRIGGER push_on_space_member_delete
AFTER DELETE ON public.space_members
FOR EACH ROW
EXECUTE FUNCTION public.notify_push_on_change();
