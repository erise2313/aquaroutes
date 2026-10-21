-- station_driver_positions(): where the caller's on-duty drivers are.
--
-- The owner's "Live Fleet Tracking" map showed the station and the stops
-- but never the drivers, although the driver app reports its position
-- while on duty (driver_states). This returns the latitude and longitude
-- the app can plot (current_location is a PostGIS point), for the owner's
-- or staff member's own station only. Off-duty drivers are left out, so
-- going off duty takes a driver off the map.
create or replace function station_driver_positions()
returns table (worker_id uuid, full_name text, worker_code text, latitude double precision, longitude double precision, last_updated timestamptz)
language sql stable security definer set search_path = public, extensions
as $$
  select w.id, w.full_name, w.worker_code,
         st_y(ds.current_location::geometry), st_x(ds.current_location::geometry),
         ds.last_updated
    from driver_states ds
    join workers w on w.id = ds.worker_id
   where ds.is_active
     and ds.current_location is not null
     and ds.station_id = coalesce(
           (select id from water_stations where owner_profile_id = auth.uid() limit 1),
           auth_staff_station_id());
$$;

revoke all on function station_driver_positions() from public, anon;
grant execute on function station_driver_positions() to authenticated;
