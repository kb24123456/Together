-- Migration 013: let public SELECT the `avatars` bucket row.
--
-- Supabase Storage's server looks up the bucket (SELECT from storage.buckets)
-- before inserting an object, even when using anon / authenticated clients.
-- storage.buckets has RLS enabled but zero policies, so the lookup default-
-- denies for non-service-role clients and the subsequent INSERT on
-- storage.objects surfaces as "new row violates row-level security policy".
--
-- Limiting the SELECT policy to `id = 'avatars'` keeps other buckets' metadata
-- private. Object reads still require a signed URL (no SELECT on
-- storage.objects). Object writes remain limited to the avatars bucket via
-- the policies from migrations 011 + 012.
DROP POLICY IF EXISTS "avatars_public_bucket_select" ON storage.buckets;
CREATE POLICY "avatars_public_bucket_select"
ON storage.buckets FOR SELECT
TO public
USING (id = 'avatars');
