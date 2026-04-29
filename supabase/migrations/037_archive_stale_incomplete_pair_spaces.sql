-- Pair spaces with fewer/more than two members and no pending/accepted invite
-- are abandoned invite shells. Keep history, but remove them from active pair
-- queries by archiving the space.

UPDATE public.spaces s
SET status = 'archived',
    archived_at = COALESCE(s.archived_at, now()),
    updated_at = now()
WHERE s.type = 'pair'
  AND s.status = 'active'
  AND NOT EXISTS (
    SELECT 1
    FROM public.pair_invites pi
    WHERE pi.space_id = s.id
      AND pi.status IN ('pending', 'accepted')
  )
  AND (
    SELECT count(*)
    FROM public.space_members sm
    WHERE sm.space_id = s.id
  ) <> 2;
