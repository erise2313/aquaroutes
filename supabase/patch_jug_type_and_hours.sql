-- =====================================================================
-- Part B: jug/container type at order time (customers pick Slim vs
-- Round, scoped to what the chosen station actually fills -- previously
-- the order form only let a customer pick a water type and a jug count,
-- never which container shape).
-- Part C: station operating days/hours, shown on the map/directory and
-- factored into whether a station is actually orderable right now (same
-- way the existing accepts_new_orders toggle already works). All new
-- fields are nullable -- a station that hasn't set anything behaves
-- exactly as it does today (always orderable, no hours shown).
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

-- ---- Part B: orders.jug_type ----
-- Plain text, matching how orders.water_type already works (not the
-- jug_type enum used by the inter-station clearinghouse/offered_jug_types
-- -- that enum is defined later in the schema than `orders`/
-- insert_quick_order, so reusing it here would create an ordering
-- dependency; a free-text column mirrors the existing water_type column's
-- own convention anyway).

alter table orders add column if not exists jug_type text;

create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered int,
  p_water_type text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total_amount numeric,
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
  v_accepts_new_orders boolean;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select is_active, accepts_new_orders into v_is_active, v_accepts_new_orders
    from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active or not coalesce(v_accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type, p_jug_type,
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id, p_scheduled_for
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- CREATE OR REPLACE cannot change a function's return-column list, only
-- drop-and-recreate can -- both of these are gaining a jug_type column.

drop function if exists get_active_orders(uuid);

create function get_active_orders(p_station_id uuid)
returns table (id uuid, lat double precision, lng double precision, jugs_ordered int, water_type text, jug_type text) as $$
  select o.id,
         st_y(o.delivery_location::geometry) as lat,
         st_x(o.delivery_location::geometry) as lng,
         o.jugs_ordered,
         o.water_type,
         o.jug_type
  from orders o
  where o.station_id = p_station_id
    and o.status in ('assigned', 'active');
$$ language sql stable security invoker;

drop function if exists lookup_guest_order(uuid, text);

create function lookup_guest_order(p_order_id uuid, p_guest_phone text)
returns table (
  id uuid, station_name text, status order_status, jugs_ordered int,
  water_type text, jug_type text, total_amount numeric, created_at timestamptz
) as $$
begin
  return query
    select o.id, s.station_name, o.status, o.jugs_ordered, o.water_type, o.jug_type, o.total_amount, o.created_at
    from orders o
    join water_stations s on s.id = o.station_id
    where o.id = p_order_id and o.guest_phone = p_guest_phone;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- Part C: water_stations operating days/hours ----

alter table water_stations add column if not exists operating_days smallint[];
alter table water_stations add column if not exists opens_at time;
alter table water_stations add column if not exists closes_at time;

drop view if exists public_stations cascade;

create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, ws.is_active,
         ws.offered_jug_types, ws.offers_jug_exchange, ws.accepts_new_orders,
         ws.operating_days, ws.opens_at, ws.closes_at,
         b.name as barangay_name,
         coalesce(r.avg_rating, 0) as avg_rating,
         coalesce(r.review_count, 0) as review_count
  from water_stations ws
  left join barangays b on b.id = ws.barangay_id
  left join (
    select station_id, avg(rating)::numeric(3,2) as avg_rating, count(*) as review_count
    from reviews
    group by station_id
  ) r on r.station_id = ws.id
  where ws.is_colorum_verified = true and ws.is_active = true;

grant select on public_stations to anon, authenticated;
