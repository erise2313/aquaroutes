-- member_station_names(): every station's id and name, for signed-in people.
--
-- Owners, staff and drivers can read only their own station's row (it holds
-- invite and staff codes), so the Clearinghouse listed the other side of
-- every balance as "Unknown Station", and the station pickers for jug
-- settlements and exchanges came back empty. Names only; nothing else.
create or replace function member_station_names()
returns table (id uuid, station_name text)
language sql stable security definer set search_path = public
as $$
  select ws.id, ws.station_name from water_stations ws order by ws.station_name;
$$;

revoke all on function member_station_names() from public, anon;
grant execute on function member_station_names() to authenticated;

-- my_station_phone(): the owner's phone for the station a driver or staff
-- member works at. The driver dashboard read it through a profiles embed,
-- which drivers can't read, so "Call Station" had no number to call.
create or replace function my_station_phone()
returns text
language sql stable security definer set search_path = public
as $$
  select p.phone_number
    from water_stations ws
    join profiles p on p.id = ws.owner_profile_id
   where ws.id = coalesce(auth_station_id(), auth_staff_station_id())
   limit 1;
$$;

revoke all on function my_station_phone() from public, anon;
grant execute on function my_station_phone() to authenticated;
