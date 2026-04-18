-- Migration 012: swap avatars bucket policies TO anon → TO public
--
-- E2E surfaced "new row violates row-level security policy" when the
-- supabase-swift SDK attempted to upload. The SDK's role does not reliably
-- match `anon` in all session configurations, so the TO anon grants from
-- migration 011 never fired. Relaxing to TO public covers every role the
-- client may be using while still keeping the bucket itself private —
-- reads continue to require a signed URL (no SELECT policy exists).
DROP POLICY IF EXISTS "avatars_anon_insert" ON storage.objects;
DROP POLICY IF EXISTS "avatars_anon_update" ON storage.objects;

CREATE POLICY "avatars_public_insert"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "avatars_public_update"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'avatars');
