-- =====================================================================
-- Adds three permit types found via research into actual Philippine
-- water-refilling-station regulations that the app didn't track yet:
-- Fire Safety Inspection Certificate (BFP, required for every station)
-- and NWRB Water Permit / Certificate of Public Convenience (required
-- only for stations drawing their own groundwater -- the WASA admin
-- decides per station via the new "required" toggle on Permit Review).
-- Also fixes a real pre-existing bug: fda_license was defined as a
-- permit type but never actually auto-inserted as required for any
-- station, even though the website always told owners it was required.
--
-- IMPORTANT: run PART 1 by itself first, wait for it to complete, THEN
-- run PART 2 in a separate execution. Postgres cannot use a newly added
-- enum value in the same transaction that added it.
-- =====================================================================

-- ---- PART 1: run this first, alone ----

alter type permit_type add value if not exists 'fire_safety_certificate';
alter type permit_type add value if not exists 'nwrb_water_permit';
alter type permit_type add value if not exists 'nwrb_certificate_of_public_convenience';

-- ---- PART 2: run this second, after Part 1 has completed ----

create or replace function sync_required_permits() returns trigger as $$
begin
  insert into permits (station_id, permit_type, is_required)
    values
      (new.id, 'business_permit', true),
      (new.id, 'sanitary_permit', true),
      (new.id, 'fda_license', true),
      (new.id, 'fire_safety_certificate', true),
      (new.id, 'nwrb_water_permit', true),
      (new.id, 'nwrb_certificate_of_public_convenience', true)
    on conflict (station_id, permit_type) do nothing;

  if 'alkaline' = any(new.offered_water_types) then
    insert into permits (station_id, permit_type, is_required)
      values
        (new.id, 'alkaline_tech_cert', true),
        (new.id, 'alkaline_water_test', true)
      on conflict (station_id, permit_type) do update set is_required = true;
  else
    update permits set is_required = false
      where station_id = new.id
        and permit_type in ('alkaline_tech_cert', 'alkaline_water_test');
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- Backfill: existing stations never got fda_license/fire_safety_certificate/
-- nwrb_* rows created (the trigger above only fires on insert/update of
-- water_stations, not retroactively). Re-run it for every existing station
-- so already-registered stations get the same rows a new registration
-- would produce.
do $$
declare
  v_station record;
begin
  for v_station in select * from water_stations loop
    insert into permits (station_id, permit_type, is_required)
      values
        (v_station.id, 'fda_license', true),
        (v_station.id, 'fire_safety_certificate', true),
        (v_station.id, 'nwrb_water_permit', true),
        (v_station.id, 'nwrb_certificate_of_public_convenience', true)
      on conflict (station_id, permit_type) do nothing;
  end loop;
end $$;
