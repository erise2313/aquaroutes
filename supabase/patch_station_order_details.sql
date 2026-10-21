-- station_order_details(): who and where, for the station's own orders.
--
-- The Live Order Pipeline showed a name only for phone and walk-in orders:
-- for an app order the owner saw "Placed at 4:55 AM", because owners can't
-- read customers' profiles. And it had no way to see the delivery point,
-- which is stored as a PostGIS point the app can't read. This returns the
-- customer's name and phone and the delivery latitude/longitude, for orders
-- of the caller's own station (owner or staff) only.
create or replace function station_order_details(p_ids uuid[])
returns table (order_id uuid, customer_name text, customer_phone text, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public
as $$
  select o.id,
         coalesce(p.full_name, o.guest_name),
         coalesce(nullif(o.customer_phone, ''), p.phone_number, o.guest_phone),
         case when o.delivery_location is null then null else st_y(o.delivery_location::geometry) end,
         case when o.delivery_location is null then null else st_x(o.delivery_location::geometry) end
    from orders o
    left join profiles p on p.id = o.customer_profile_id
   where o.id = any(p_ids)
     and o.station_id = coalesce(
           (select id from water_stations where owner_profile_id = auth.uid() limit 1),
           auth_staff_station_id());
$$;

revoke all on function station_order_details(uuid[]) from public, anon;
grant execute on function station_order_details(uuid[]) to authenticated;
