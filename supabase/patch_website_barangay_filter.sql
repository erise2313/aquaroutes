-- =====================================================================
-- Incremental patch: adds barangay_name to the public_stations view, for
-- the website's Stations directory filter (screens/web/stations_directory_screen.dart).
-- Additive/corrective -- no data loss. Paste into the Supabase SQL Editor
-- and run once. Safe to re-run.
-- =====================================================================

drop view if exists public_stations cascade;

create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, b.name as barangay_name
  from water_stations ws
  left join barangays b on b.id = ws.barangay_id
  where ws.is_colorum_verified = true and ws.is_active = true;

grant select on public_stations to anon, authenticated;
