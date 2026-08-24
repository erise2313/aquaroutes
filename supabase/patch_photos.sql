-- =====================================================================
-- Incremental patch: profile avatars, station photos, bulletin post
-- images. Additive to your existing schema -- no data loss.
-- =====================================================================

alter table water_stations add column photo_url text;
alter table bulletins add column image_url text;

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('station-photos', 'station-photos', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('bulletin-images', 'bulletin-images', true) on conflict (id) do nothing;

-- Refresh the public_stations view to include photo_url.
drop view if exists public_stations cascade;
create view public_stations as
  select id, station_name, station_address, latitude, longitude,
         price_per_jug, delivery_fee, offered_water_types, photo_url,
         is_colorum_verified, is_accredited
  from water_stations
  where is_colorum_verified = true;
grant select on public_stations to anon, authenticated;

create policy avatars_self_write on storage.objects for all
  using (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid())
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid());

create policy station_photos_owner_write on storage.objects for all
  using (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  )
  with check (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  );

create policy bulletin_images_poster_write on storage.objects for insert
  with check (
    bucket_id = 'bulletin-images'
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );
