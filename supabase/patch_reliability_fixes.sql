-- =====================================================================
-- Incremental patch: reliability fixes found during a focused review of
-- the registration, bulletin-posting, and order-placement flows.
-- Additive/corrective to your existing schema -- no data loss. Paste into
-- the Supabase SQL Editor and run once. Safe to re-run.
--
--   1. register_driver_for_station() is now idempotent -- a retried call
--      (e.g. network retry) for a profile that already has a worker row
--      returns the existing worker instead of hitting a raw unique-
--      violation error. (register_station_owner and register_customer
--      already had this from an earlier patch.)
--   2. orders.client_request_id -- a client-generated idempotency key
--      (quick_order_screen.dart) so a genuine network-retry double-submit
--      (request succeeded server-side but the client never saw the
--      response) returns the existing order instead of creating a second
--      one. A manual double-tap was already blocked by the UI disabling
--      the submit button -- this covers the case that couldn't be.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. register_driver_for_station: idempotent retry
-- ---------------------------------------------------------------------
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
begin
  select id into v_worker_id from workers where profile_id = auth.uid();
  if v_worker_id is not null then
    return v_worker_id;
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

-- ---------------------------------------------------------------------
-- 2. orders.client_request_id + insert_quick_order idempotency check
-- ---------------------------------------------------------------------
alter table orders add column if not exists client_request_id text;

create unique index if not exists orders_client_request_id_key
  on orders (client_request_id) where client_request_id is not null;

drop function if exists insert_quick_order(uuid, double precision, double precision, int, text, numeric, numeric, numeric, text, text);

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
  p_client_request_id text default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select is_active into v_is_active from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active then
    raise exception 'This station is not currently accepting orders.';
  end if;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type,
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;
