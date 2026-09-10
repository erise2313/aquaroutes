-- =====================================================================
-- Server-side order pricing (Phase 1 of the product-catalog work).
--
-- Before this patch, insert_quick_order stored p_subtotal, p_delivery_fee
-- and p_total_amount exactly as the phone sent them. It runs SECURITY
-- DEFINER and is executable by anon, so anyone -- no sign-in needed --
-- could place an order at any price they liked; the driver would then
-- collect whatever the order said. Quantity, water type and container were
-- not validated either. (There were no orders in the live database when
-- this was found, so nothing had been exploited.)
--
-- This patch:
--   1. Drops two stale overloads left behind by earlier patches.
--   2. Makes the server the only thing that decides what an order costs.
--      The money parameters are kept purely so existing callers -- the
--      current app and already-installed test APKs -- keep resolving to
--      this function unchanged. Their values are ignored.
--   3. Stops the floor-price trigger firing when nothing it checks changed.
--      It was declared "UPDATE OF price_per_jug, offered_water_types",
--      which fires whenever those columns are in the SET list -- and the
--      station profile screen always sends offered_water_types -- so any
--      profile save by a station priced under a floor failed, even a name
--      change.
--   4. Clears the test floor prices (purified 100 / mineral 380 /
--      alkaline 55) until the association sets real ones.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Stale overloads. The app always calls with all 14 named parameters
--    (lib/services/order_service.dart), which resolves to the version
--    replaced below; these two only existed as leftovers, and both skip
--    the jug-exchange validation the current version does.
-- ---------------------------------------------------------------------
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz);
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz, text);

-- ---------------------------------------------------------------------
-- 2. Server-computed money. Same argument list as before, so this is a
--    true replacement rather than a new overload.
-- ---------------------------------------------------------------------
create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,        -- IGNORED: kept for caller compatibility
  p_delivery_fee numeric,    -- IGNORED: kept for caller compatibility
  p_total_amount numeric,    -- IGNORED: kept for caller compatibility
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  s water_stations%rowtype;
  v_origin uuid;
  v_subtotal numeric(10,2);
  -- Default ceiling per order; for the association to confirm.
  v_max_jugs constant integer := 50;
begin
  -- Idempotent replay: a retried request returns the order it already made.
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select * into s from water_stations where id = p_station_id;

  -- Same visibility rule as the public_stations view: a station customers
  -- can't see must not be orderable by calling this function directly.
  if not found or not s.is_active or not s.is_colorum_verified then
    raise exception 'This station is not available for ordering.';
  end if;
  if not coalesce(s.accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;

  if p_jugs_ordered is null or p_jugs_ordered < 1 or p_jugs_ordered > v_max_jugs then
    raise exception 'Please order between 1 and % jugs.', v_max_jugs;
  end if;
  if p_water_type is null or not (p_water_type = any(s.offered_water_types)) then
    raise exception 'This station does not offer % water.', coalesce(p_water_type, 'that');
  end if;
  -- A station that declares containers must be ordered in one of them.
  if cardinality(coalesce(s.offered_jug_types::text[], '{}')) > 0
     and (p_jug_type is null or not (p_jug_type = any(s.offered_jug_types::text[]))) then
    raise exception 'This station does not offer that container.';
  end if;
  if s.price_per_jug is null or s.price_per_jug <= 0 then
    raise exception 'This station has not set its prices yet.';
  end if;

  v_subtotal := p_jugs_ordered * s.price_per_jug;

  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(s.offers_jug_exchange, false)
    then p_jug_exchange_origin_station_id
    else null
  end;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for,
    jug_exchange_origin_station_id
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type, p_jug_type,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 3. Floor-price check only when something it checks actually changed.
--    Done in the function rather than a trigger WHEN clause, because a
--    trigger covering INSERT can't reference OLD.
-- ---------------------------------------------------------------------
create or replace function enforce_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
begin
  if tg_op = 'UPDATE'
     and new.price_per_jug is not distinct from old.price_per_jug
     and new.offered_water_types is not distinct from old.offered_water_types then
    return new;
  end if;

  select max(min_price_per_jug) into v_floor
    from floor_prices
    where association_id = new.association_id
      and water_type = any(new.offered_water_types);

  if v_floor is not null and new.price_per_jug < v_floor then
    raise exception 'price_per_jug (%) is below the association floor price (%) for one or more offered water types.', new.price_per_jug, v_floor;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 4. Test floor prices out until the association sets real ones.
-- ---------------------------------------------------------------------
delete from floor_prices;
