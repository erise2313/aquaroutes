-- =====================================================================
-- Fix: a flagged driver could rejoin the association by re-registering.
--
-- There are two ways a driver joins a station, and only one of them
-- checked clearance:
--
--   driver_switch_station()        raises if clearance_status = 'flagged'
--   register_driver_for_station()  did not check at all
--
-- So the sequence below let a flagged driver straight back in:
--
--   1. Station A files an incident; a WASA admin confirms it, which sets
--      the worker's clearance_status to 'flagged'.
--   2. Station A removes the driver (owner_remove_worker), leaving
--      workers.station_id null.
--   3. The driver enters any station's invite code.
--   4. register_driver_for_station() takes its "previously left/removed"
--      re-link branch, which never looked at clearance, and adds them to
--      the new station's roster.
--
-- A driver who was NOT removed is blocked by driver_switch_station. Being
-- removed after an incident therefore made it easier to move, not harder
-- -- the opposite of what the worker security registry exists to do, and
-- the opposite of what the public website states:
--
--   "Maintains a shared worker security registry, so a driver flagged for
--    an incident at one station can't simply move to another unnoticed."
--
-- Found during the functionality evaluation of 10 October 2026, while
-- checking an evaluator's observation that the station invite code never
-- rotates -- which is what makes step 3 easy, since a removed driver
-- already knows it.
--
-- The check below is deliberately worded like the one in
-- driver_switch_station, so a flagged driver gets the same explanation
-- whichever route they try.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function register_driver_for_station(
  p_invite_code text,
  p_full_name text,
  p_phone_number text,
  p_vehicle_plate text,
  p_jug_capacity int
) returns uuid as $$
declare
  v_station_id uuid;
  v_association_id uuid;
  v_worker_id uuid;
  v_current_station_id uuid;
  v_clearance clearance_status;
begin
  select id, station_id, clearance_status
    into v_worker_id, v_current_station_id, v_clearance
    from workers where profile_id = auth.uid();

  if v_worker_id is not null then
    if v_current_station_id is not null then
      return v_worker_id;
    end if;

    -- The fix. Checked only on the re-link branch: a brand new worker
    -- (further down) starts at 'pending_clearance', which must stay
    -- joinable or nobody could ever register in the first place.
    if v_clearance = 'flagged' then
      raise exception 'Cannot join a station while flagged. Contact WASA to resolve outstanding incidents.';
    end if;

    -- Previously left/removed from a station -- re-link to the new one
    -- instead of silently returning a stale, still-unlinked id.
    select id, association_id into v_station_id, v_association_id
      from water_stations where invite_code ilike p_invite_code;
    if v_station_id is null then
      raise exception 'Invalid station invite code.';
    end if;

    update workers set station_id = v_station_id, updated_at = now() where id = v_worker_id;
    update memberships set station_id = v_station_id, association_id = v_association_id
      where profile_id = auth.uid() and role = 'driver';
    insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_station_id);
    return v_worker_id;
  end if;

  if exists (select 1 from memberships where profile_id = auth.uid()) then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
  end if;

  select id, association_id into v_station_id, v_association_id
    from water_stations where invite_code ilike p_invite_code;

  if v_station_id is null then
    raise exception 'Invalid station invite code.';
  end if;

  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity)
    values (v_station_id, auth.uid(), p_full_name, p_phone_number, p_vehicle_plate, p_jug_capacity)
    returning id into v_worker_id;

  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_station_id);

  insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'driver', v_station_id);

  return v_worker_id;
end;
$$ language plpgsql security definer set search_path = public;

-- =====================================================================
-- VERIFY -- both join paths should now refuse a flagged driver.
-- =====================================================================
select
  p.proname as function_name,
  case when pg_get_functiondef(p.oid) like '%flagged%'
       then 'checks clearance' else 'NO CHECK' end as clearance_guard
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('register_driver_for_station', 'driver_switch_station')
order by p.proname;
