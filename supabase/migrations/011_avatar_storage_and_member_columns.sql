-- Migration 011: avatar sync columns + private Storage bucket
--
-- Changes:
-- 1. space_members gains avatar_asset_id + avatar_system_name text columns
--    to carry the full avatar metadata (previously only avatar_url + version
--    survived the push, making the receiving device unable to resolve the
--    partner's avatar).
-- 2. Creates a private Storage bucket `avatars` + permissive anon INSERT/UPDATE
--    RLS (project uses anon-key auth model; see project_identity_model memory).
--    SELECT is intentionally left without a policy — reads must go via a
--    signed URL, which bypasses RLS.

ALTER TABLE public.space_members
    ADD COLUMN IF NOT EXISTS avatar_asset_id text,
    ADD COLUMN IF NOT EXISTS avatar_system_name text;

-- Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

-- RLS on storage.objects for this bucket
DROP POLICY IF EXISTS "avatars_anon_insert" ON storage.objects;
CREATE POLICY "avatars_anon_insert"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (bucket_id = 'avatars');

DROP POLICY IF EXISTS "avatars_anon_update" ON storage.objects;
CREATE POLICY "avatars_anon_update"
ON storage.objects FOR UPDATE
TO anon
USING (bucket_id = 'avatars');

-- Explicitly NO SELECT policy for anon. Reads must use signed URLs
-- generated server-side or by the owner client.
