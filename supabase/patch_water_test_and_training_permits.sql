-- =====================================================================
-- Closes the last two gaps between the actual permit set the app tracks
-- and Philippine water-refilling-station regulation research: routine
-- water quality testing and operator training were never represented as
-- their own permit types at all (the app only tracked the alkaline-
-- specific water test, not the general one every station -- alkaline or
-- not -- is expected to run under PNSDW).
--
-- New permit types, both required for every station unconditionally
-- (same pattern as business_permit/sanitary_permit/fda_license):
--   - water_quality_test_report        (DOH, monthly/biannual testing)
--   - operator_training_certificate    (CCWRSPO, 40-hour course)
--
-- These are independent of, and do not replace, the existing alkaline-
-- specific alkaline_water_test permit -- a station offering alkaline
-- water still needs BOTH the general water_quality_test_report and the
-- alkaline-specific alkaline_water_test.
--
-- IMPORTANT: run PART 1 by itself first, wait for it to complete, THEN
-- run PART 2 in a separate execution. Postgres cannot use a newly added
-- enum value in the same transaction that added it.
-- =====================================================================

-- ---- PART 1: run this first, alone ----

alter type permit_type add value if not exists 'water_quality_test_report';
alter type permit_type add value if not exists 'operator_training_certificate';

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
      (new.id, 'nwrb_certificate_of_public_convenience', true),
      (new.id, 'water_quality_test_report', true),
      (new.id, 'operator_training_certificate', true)
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

-- Backfill: existing stations never got water_quality_test_report/
-- operator_training_certificate rows created (the trigger above only
-- fires on insert/update of water_stations, not retroactively). Re-run
-- it for every existing station so already-registered stations get the
-- same rows a new registration would produce.
do $$
declare
  v_station record;
begin
  for v_station in select * from water_stations loop
    insert into permits (station_id, permit_type, is_required)
      values
        (v_station.id, 'water_quality_test_report', true),
        (v_station.id, 'operator_training_certificate', true)
      on conflict (station_id, permit_type) do nothing;
  end loop;
end $$;
