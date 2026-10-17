-- =====================================================================
-- Two fixes, both idempotent -- safe to run more than once.
--
-- 1. Posting a bulletin with a picture always failed.
--
--    PhotoService uploads with `upsert: true`, which the Storage API turns
--    into INSERT ... ON CONFLICT DO UPDATE ... RETURNING. Postgres checks
--    that against the SELECT and UPDATE policies as well as INSERT, and
--    bulletin-images only ever had an INSERT policy -- so every upload was
--    refused by RLS, for owners, drivers and admins alike. Nothing has ever
--    been stored in the bucket. Avatars and station photos work because
--    their policies are `for all`.
--
--    The same gap made PhotoService.deleteBulletinImage (the clean-up after
--    a failed post) a silent no-op, since there was no DELETE policy.
--
--    Replaced with a `for all` policy on the same condition, matching
--    avatars_self_write: a poster can read, overwrite and delete only files
--    under their own {profile_id}/ folder. The bucket stays public, so the
--    published URLs are unaffected.
--
-- 2. associations and barangays had RLS off.
--
--    Supabase flagged both as fully writable by anyone holding the
--    publishable key, which ships in every APK and web build. The app only
--    reads them (bulletin_service.dart, about_screen.dart,
--    about_info_screen.dart); changes go through security definer
--    functions or the SQL editor, which RLS does not affect. So: RLS on,
--    public read, no client writes.
--
--    spatial_ref_sys is PostGIS's own table, owned by the extension, and is
--    left as Supabase ships it.
-- =====================================================================

-- 1. bulletin-images
drop policy if exists bulletin_images_poster_write on storage.objects;
create policy bulletin_images_poster_write on storage.objects for all
  using (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  )
  with check (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );

-- 2. reference tables
alter table associations enable row level security;
alter table barangays enable row level security;

drop policy if exists associations_public_read on associations;
create policy associations_public_read on associations for select using (true);

drop policy if exists barangays_public_read on barangays;
create policy barangays_public_read on barangays for select using (true);

-- =====================================================================
-- VERIFY
-- =====================================================================
select 'bulletin_images_poster_write' as item, cmd as result
  from pg_policies where schemaname = 'storage' and policyname = 'bulletin_images_poster_write'
union all
select c.relname || ' RLS', case when c.relrowsecurity then 'on' else 'OFF' end
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('associations', 'barangays');
-- Expect: ALL, on, on.
