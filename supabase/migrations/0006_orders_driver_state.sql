-- Orders + live driver location state. Orders now support anonymous public
-- "quick orders" (guest_name/guest_phone) alongside authenticated customers,
-- and reference workers (not profiles) as the assigned driver so unregistered
-- workers can still be dispatched and tracked.

create type order_status as enum ('pending', 'assigned', 'active', 'done', 'cancelled');

create table orders (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id),
  customer_profile_id uuid references profiles(id),
  guest_name text,
  guest_phone text,
  driver_worker_id uuid references workers(id),
  delivery_location geography(point, 4326) not null,
  jugs_ordered int not null check (jugs_ordered > 0),
  water_type text not null default 'purified',
  status order_status not null default 'pending',
  payment_method text not null default 'cash',
  subtotal numeric(10,2) not null,
  delivery_fee numeric(10,2) not null,
  total_amount numeric(10,2) not null,
  customer_phone text,
  empty_jugs_returned int,
  payment_collected boolean,
  created_at timestamptz not null default now(),
  -- Client-generated idempotency key (quick_order_screen.dart) -- protects
  -- against a genuine network-retry double-submit (request succeeded
  -- server-side but the client never saw the response, so the UI's
  -- submit-button disable didn't help): insert_quick_order() checks this
  -- first and returns the existing order instead of creating a second one.
  client_request_id text,
  constraint customer_or_guest check (customer_profile_id is not null or guest_name is not null)
);

create index orders_station_status_idx on orders (station_id, status);
create index orders_customer_idx on orders (customer_profile_id);
create index orders_driver_worker_idx on orders (driver_worker_id);
create unique index orders_client_request_id_key on orders (client_request_id) where client_request_id is not null;

create table driver_states (
  worker_id uuid primary key references workers(id) on delete cascade,
  station_id uuid not null references water_stations(id),
  current_location geography(point, 4326),
  current_speed double precision,
  -- The ON-DUTY broadcast toggle -- absent from the old schema, which had
  -- no on/off concept at all.
  is_active boolean not null default false,
  last_updated timestamptz not null default now()
);

create index driver_states_station_idx on driver_states (station_id);

-- Station-scoped active-order pins, for the owner's fleet map and the
-- driver's manifest. Replaces the old client-trusted RPC parameter with
-- one still scoped by station_id, but real enforcement lives in RLS
-- (0009_rls.sql) since this function runs security invoker.
create or replace function get_active_orders(p_station_id uuid)
returns table (id uuid, lat double precision, lng double precision, jugs_ordered int) as $$
  select o.id,
         st_y(o.delivery_location::geometry) as lat,
         st_x(o.delivery_location::geometry) as lng,
         o.jugs_ordered
  from orders o
  where o.station_id = p_station_id
    and o.status in ('assigned', 'active');
$$ language sql stable security invoker;

-- Builds the PostGIS point server-side instead of the old client-side raw
-- WKT string interpolation ('POINT(lng lat)') used by place_order_screen.dart
-- and sandbox_screen.dart. Supports both authenticated and guest orders.
-- security definer (not invoker) so the is_active lookup below can read
-- water_stations regardless of caller -- there's no RLS SELECT policy
-- granting arbitrary/anon read access to that table directly (only via the
-- public_stations view), and this function needs to read it for every caller.
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
  -- Idempotency check: a genuine network-retry (request succeeded but the
  -- client never saw the response) would otherwise create a second order,
  -- since the UI's submit-button disable only blocks a manual double-tap,
  -- not a retried request. Same client_request_id -> return the order that
  -- already exists instead of creating another.
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

-- orders_driver_update (0009_rls.sql) grants a driver UPDATE on every
-- column of their station's orders, not just operational ones -- without
-- this guard a driver could quietly alter subtotal/delivery_fee/
-- total_amount/jugs_ordered/station_id on a delivery while marking it
-- paid. station_owner/wasa_admin are unrestricted (they set these values
-- legitimately, e.g. when assigning/adjusting an order).
create or replace function protect_order_financial_fields() returns trigger as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    if new.subtotal is distinct from old.subtotal
       or new.delivery_fee is distinct from old.delivery_fee
       or new.total_amount is distinct from old.total_amount
       or new.jugs_ordered is distinct from old.jugs_ordered
       or new.station_id is distinct from old.station_id then
      raise exception 'Drivers may not modify order financial or station details.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_protect_order_financial_fields
  before update on orders
  for each row execute function protect_order_financial_fields();
