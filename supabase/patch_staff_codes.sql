-- Every station always has a staff code, and each join path says plainly
-- when someone typed the other kind of code.
--
-- Staff codes only existed once an owner pressed "Create a staff code" on
-- Team, which nobody had done, so the only code anyone saw was the drivers'
-- one on the dashboard. Staff registering with it were refused with
-- "Invalid staff code". The two codes stay separate on purpose: a driver
-- code must not make someone staff (staff see the station's orders and
-- customer contacts).

-- 1. New stations get a staff code when they are created.
create or replace function fill_staff_invite_code()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.staff_invite_code is null then
    new.staff_invite_code := new_invite_code();
  end if;
  return new;
end;
$$;

create or replace trigger trg_fill_staff_invite_code
  before insert on water_stations
  for each row execute function fill_staff_invite_code();

-- 2. Existing stations. The three test stations get readable codes for the
-- test accounts sheet; the rest get random ones. No expiry, like the
-- stations' existing driver codes; issuing a new one from Team sets the
-- association's validity period.
update water_stations set staff_invite_code = 'STAFFBV'
  where invite_code = 'BUENAV1' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFBV');
update water_stations set staff_invite_code = 'STAFFNV'
  where station_name = 'Navarro Springs Water Station' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFNV');
update water_stations set staff_invite_code = 'STAFFTJ'
  where invite_code = 'TEJERO1' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFTJ');
update water_stations set staff_invite_code = new_invite_code()
  where staff_invite_code is null;

-- 3. Staff who type the driver code are told which code they need.
create or replace function register_staff_for_station(p_staff_code text, p_full_name text, p_phone_number text)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_station_id uuid;
  v_association_id uuid;
  v_expires timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  select station_id into v_station_id from memberships
   where profile_id = auth.uid() and role = 'station_staff' and status = 'active';
  if v_station_id is not null then
    return v_station_id;
  end if;
  if exists (select 1 from memberships where profile_id = auth.uid() and status = 'active') then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
  end if;

  select id, association_id, staff_invite_expires_at into v_station_id, v_association_id, v_expires
    from water_stations where staff_invite_code ilike trim(p_staff_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code ilike trim(p_staff_code)) then
      raise exception 'That is the station''s driver code. Staff need the station''s staff code -- the owner finds it on their dashboard or Team page.';
    end if;
    raise exception 'Invalid staff code. Ask the station owner for the staff code (not the driver code).';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This staff code has expired. Ask the station owner for a new one.';
  end if;

  insert into profiles (id, full_name, phone_number)
  values (auth.uid(), coalesce(nullif(trim(p_full_name), ''), ''), nullif(trim(p_phone_number), ''))
  on conflict (id) do update
    set full_name = coalesce(nullif(trim(excluded.full_name), ''), profiles.full_name),
        phone_number = coalesce(excluded.phone_number, profiles.phone_number),
        updated_at = now();

  update memberships set role = 'station_staff', station_id = v_station_id, association_id = v_association_id, status = 'active'
   where profile_id = auth.uid() and role = 'station_staff';
  if not found then
    insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'station_staff', v_station_id);
  end if;

  insert into notifications (profile_id, category, title, body, station_id)
  select ws.owner_profile_id, 'account', 'New staff member',
         coalesce(nullif(trim(p_full_name), ''), 'Someone') || ' joined your station as staff.', ws.id
    from water_stations ws where ws.id = v_station_id and ws.owner_profile_id is not null;
  return v_station_id;
end;
$function$;

-- 4. Drivers who type the staff code are told the same, the other way round.
create or replace function register_driver_for_station(p_invite_code text, p_full_name text, p_phone_number text, p_vehicle_plate text, p_jug_capacity integer)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_station_id uuid;
  v_association_id uuid;
  v_expires timestamptz;
  v_worker_id uuid;
  v_current_station_id uuid;
  v_clearance clearance_status;
begin
  select id, station_id, clearance_status
    into v_worker_id, v_current_station_id, v_clearance
    from workers where profile_id = auth.uid();

  if v_worker_id is not null and v_current_station_id is not null then
    return v_worker_id;
  end if;

  select id, association_id, invite_code_expires_at into v_station_id, v_association_id, v_expires
    from water_stations where invite_code ilike trim(p_invite_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where staff_invite_code ilike trim(p_invite_code)) then
      raise exception 'That is the station''s staff code. Drivers need the station''s driver invite code from the owner''s dashboard.';
    end if;
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  if v_worker_id is not null then
    if v_clearance = 'flagged' then
      raise exception 'Cannot join a station while flagged. Contact WASA to resolve outstanding incidents.';
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

  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity)
    values (v_station_id, auth.uid(), p_full_name, p_phone_number, p_vehicle_plate, p_jug_capacity)
    returning id into v_worker_id;
  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_station_id);
  insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'driver', v_station_id);
  return v_worker_id;
end;
$function$;

-- VERIFY: select station_name, invite_code, staff_invite_code from water_stations order by 1;
