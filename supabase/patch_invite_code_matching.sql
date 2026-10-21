-- Invite and staff codes match the way people type them.
--
-- Codes were matched exactly apart from letter case, so a driver who typed
-- the letter O for a zero ("6C8OLK" for 6C80LK), I for a one, or a space
-- was told the code was invalid. Older stations' codes were made by the app
-- with all 36 characters, so these look-alikes occur. Both sides are now
-- compared in a normal form: no spaces, upper case, O read as 0, I as 1.

create or replace function invite_code_key(p_code text)
returns text
language sql immutable
as $$
  select translate(upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g')), 'OI', '01');
$$;

create or replace function driver_switch_station(p_invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_worker_id uuid;
  v_clearance clearance_status;
  v_new_station_id uuid;
  v_association_id uuid;
  v_expires timestamptz;
begin
  select id, clearance_status into v_worker_id, v_clearance from workers where profile_id = auth.uid();
  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;
  if v_clearance = 'flagged' then
    raise exception 'Cannot switch stations while flagged. Contact WASA to resolve outstanding incidents.';
  end if;

  select id, association_id, invite_code_expires_at into v_new_station_id, v_association_id, v_expires
    from water_stations where invite_code_key(invite_code) = invite_code_key(p_invite_code);
  if v_new_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_invite_code)) then
      raise exception 'That is the station''s staff code. Drivers need the station''s driver invite code from the owner''s dashboard.';
    end if;
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');
  perform set_config('gentri.trusted_order_change', 'off', true);
  update workers set station_id = v_new_station_id, updated_at = now() where id = v_worker_id;
  update memberships set station_id = v_new_station_id, association_id = v_association_id
    where profile_id = auth.uid() and role = 'driver';
  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_new_station_id);
end;
$function$;

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
    from water_stations where invite_code_key(invite_code) = invite_code_key(p_invite_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_invite_code)) then
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
    from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_staff_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(invite_code) = invite_code_key(p_staff_code)) then
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

-- VERIFY: select invite_code_key(' tejer01 ') = invite_code_key('TEJERO1');  -- true
