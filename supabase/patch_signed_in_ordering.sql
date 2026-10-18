-- =====================================================================
-- Ordering requires a signed-in customer account -- on the server too.
--
-- The app stopped offering guest checkout some time ago: the order form
-- shows a sign-in gate to visitors (quick_order_screen.dart), so every order
-- is tied to a real account. The server never followed. insert_quick_order
-- still accepted calls from signed-out visitors, holding nothing but the
-- publishable key that ships in every APK and web build, and stored them as
-- guest orders -- so anyone could skip the app and send stations orders that
-- no account stood behind.
--
-- This patch:
--
--   1. insert_quick_order refuses anyone who isn't a signed-in, active
--      customer, and records the order against that account. p_guest_name
--      and p_guest_phone keep their places in the signature so the app
--      doesn't break mid-update; p_guest_phone now only carries the contact
--      number for the delivery (orders.customer_phone), as it already did
--      for signed-in orders.
--
--   2. The guest-tracking path goes. A guest could look an order up, follow
--      its driver on the map and cancel it with the order ID and checkout
--      phone number. With no new guest orders that path only served three
--      old, closed orders (the last placed 11 September 2026), so:
--        - get_active_delivery_driver answers only the customer who placed
--          the order;
--        - lookup_guest_order is no longer callable from the app;
--        - signed-out visitors can no longer call set_order_status, whose
--          guest-cancel branch they were the only route into.
--
-- The old guest orders stay in the database, unchanged, for the record.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- 1.
create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total_amount numeric,
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null,
  p_product_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  s water_stations%rowtype;
  p station_products%rowtype;
  c container_types%rowtype;
  v_origin uuid;
  v_subtotal numeric(10,2);
  v_matches integer;
  v_max_qty constant integer := 50;
begin
  if auth.uid() is null then
    raise exception 'Sign in to place an order.';
  end if;
  if not auth_has_role('public_consumer') then
    raise exception 'Only customer accounts can place orders.';
  end if;

  if p_client_request_id is not null then
    -- A retried submit returns the order it already created -- but only
    -- the caller's own, so a request id can't fish out someone else's.
    select id into new_order_id from orders
     where client_request_id = p_client_request_id and customer_profile_id = auth.uid();
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select * into s from water_stations where id = p_station_id;
  if not found or not s.is_active or not s.is_colorum_verified then
    raise exception 'This station is not available for ordering.';
  end if;
  if not coalesce(s.accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;
  if p_jugs_ordered is null or p_jugs_ordered < 1 or p_jugs_ordered > v_max_qty then
    raise exception 'Please order a quantity between 1 and %.', v_max_qty;
  end if;
  if not exists (select 1 from station_products where station_id = p_station_id and is_available) then
    raise exception 'This station has not listed any products yet.';
  end if;

  if p_product_id is not null then
    select * into p from station_products where id = p_product_id and station_id = p_station_id;
    if not found then
      raise exception 'That product is not sold by this station.';
    end if;
  else
    if p_jug_type is not null then
      select * into p from station_products
        where station_id = p_station_id and water_type = p_water_type
          and container_code = p_jug_type and kind = 'refill';
    else
      select count(*) into v_matches from station_products
        where station_id = p_station_id and water_type = p_water_type
          and kind = 'refill' and is_available;
      if v_matches > 1 then
        raise exception 'Please choose a container.';
      elsif v_matches = 1 then
        select * into p from station_products
          where station_id = p_station_id and water_type = p_water_type
            and kind = 'refill' and is_available;
      end if;
    end if;
    if p.id is null then
      raise exception 'This station does not offer % water in that container.', coalesce(p_water_type, 'that');
    end if;
  end if;

  if not p.is_available then
    raise exception 'That product is currently unavailable.';
  end if;
  select * into c from container_types where code = p.container_code;
  if not found or not c.is_active then
    raise exception 'That container is no longer offered.';
  end if;

  v_subtotal := p_jugs_ordered * p.price;

  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(s.offers_jug_exchange, false)
      and p.kind = 'refill' and c.is_returnable
    then p_jug_exchange_origin_station_id
    else null
  end;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for,
    jug_exchange_origin_station_id, product_id, unit_price, product_kind
  ) values (
    p_station_id, auth.uid(), null, null,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p.water_type, p.container_code,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin, p.id, p.price, p.kind
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- 2.
create or replace function get_active_delivery_driver(p_order_id uuid, p_guest_phone text default null)
returns table(driver_name text, driver_phone text, lat double precision, lng double precision, last_updated timestamptz)
as $$
declare
  v_order orders%rowtype;
begin
  -- p_guest_phone is ignored; it stays in the signature for older builds.
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found.';
  end if;

  if auth.uid() is null or v_order.customer_profile_id is distinct from auth.uid() then
    raise exception 'Not authorized to view this order.';
  end if;

  if v_order.status not in ('assigned', 'active') then
    return;
  end if;

  return query
    select w.full_name, w.phone_number,
           st_y(ds.current_location::geometry) as lat,
           st_x(ds.current_location::geometry) as lng,
           ds.last_updated
    from workers w
    left join driver_states ds on ds.worker_id = w.id
    where w.id = v_order.driver_worker_id;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) from public, anon;
grant execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) to authenticated;

revoke execute on function get_active_delivery_driver(uuid, text) from public, anon;
grant execute on function get_active_delivery_driver(uuid, text) to authenticated;

revoke execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) from public, anon;
grant execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) to authenticated;

revoke execute on function lookup_guest_order(uuid, text) from public, anon, authenticated;

-- =====================================================================
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when ok then 'ok' else 'NOT APPLIED' end as result from (values
  ('visitors cannot place orders', not has_function_privilege('anon', 'public.insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid)', 'execute')),
  ('customers can place orders', has_function_privilege('authenticated', 'public.insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid)', 'execute')),
  ('visitors cannot change orders', not has_function_privilege('anon', 'public.set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean)', 'execute')),
  ('visitors cannot follow drivers', not has_function_privilege('anon', 'public.get_active_delivery_driver(uuid, text)', 'execute')),
  ('guest lookup closed', not has_function_privilege('anon', 'public.lookup_guest_order(uuid, text)', 'execute')
                          and not has_function_privilege('authenticated', 'public.lookup_guest_order(uuid, text)', 'execute'))
) as t(item, ok);
