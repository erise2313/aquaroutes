-- order_customer_contact(): the customer's name and phone for one order.
--
-- The driver dashboard read these through a profiles(...) embed, but drivers
-- can't read other people's profiles, so every delivery said "Deliver to:
-- Water Customer" with no number to call. This returns the two fields only,
-- and only to the driver assigned to the order while it is being delivered,
-- or to that station's owner or staff. Officers are not included: customer
-- identity on orders stays hidden from them unless a report is linked
-- (admin_list_orders handles that case).
create or replace function order_customer_contact(p_order_id uuid)
returns table (full_name text, phone_number text)
language sql stable security definer set search_path = public
as $$
  select coalesce(p.full_name, o.guest_name),
         coalesce(nullif(o.customer_phone, ''), p.phone_number, o.guest_phone)
  from orders o
  left join profiles p on p.id = o.customer_profile_id
  where o.id = p_order_id
    and (
      (o.status in ('assigned', 'active')
        and exists (select 1 from workers w where w.id = o.driver_worker_id and w.profile_id = auth.uid()))
      or exists (select 1 from water_stations ws where ws.id = o.station_id and ws.owner_profile_id = auth.uid())
      or o.station_id = auth_staff_station_id()
    );
$$;

revoke all on function order_customer_contact(uuid) from public, anon;
grant execute on function order_customer_contact(uuid) to authenticated;

-- VERIFY: select * from order_customer_contact('<order id>');  -- as the assigned driver
