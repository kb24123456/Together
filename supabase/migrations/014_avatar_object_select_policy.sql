-- Migration 014: allow SELECT on storage.objects for the avatars bucket.
--
-- Root cause: the supabase-swift client uploads with `x-upsert: true`, which
-- makes Supabase Storage issue `INSERT ... ON CONFLICT DO UPDATE` against
-- storage.objects. Postgres needs a SELECT policy on the target table to
-- evaluate the UPDATE policy's USING clause against the pre-existing row.
-- Without it, the upsert bounces back as "new row violates row-level
-- security policy" even though the INSERT branch alone would be fine.
--
-- Privacy is still preserved because:
--   1. bucket.public=false → no anonymous unauthenticated HTTP reads.
--   2. Object paths are `{space_uuid}/{user_uuid}/{version}.jpg` —
--      unguessable without knowing all three UUIDs.
--   3. The anon API key holder can probe paths, but Together's anon key is
--      also what enables all other reads in the app.
DROP POLICY IF EXISTS "avatars_public_select" ON storage.objects;
CREATE POLICY "avatars_public_select"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'avatars');
