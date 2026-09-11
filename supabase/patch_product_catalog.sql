-- =====================================================================
-- Per-station product catalog (Phase 2 of the pricing work).
--
-- Replaces "one price for everything" with products a station actually
-- sells: water type x container x (refill | new container), each with its
-- own price. Container sizes become a list the association manages.
-- Order prices keep coming from the server (patch_server_side_pricing.sql);
-- they now come from the product instead of a single station price.
--
-- Compatibility is deliberate throughout:
--   * water_stations.offered_water_types / offered_jug_types / price_per_jug
--     are kept, but DERIVED from available products by trigger. Every
--     existing reader -- public_stations, the directory filters, the jug
--     exchange, sync_required_permits (alkaline permits) -- keeps working,
--     and price_per_jug becomes the "from" price shown in listings.
--   * insert_quick_order still accepts the old call shape (water type +
--     container, no product id), resolving the refill product itself, so
--     app builds already installed on test phones keep ordering correctly.
--   * The two 5-gallon container codes reuse the jug-ledger enum strings,
--     so orders.jug_type and the clearinghouse keep working untouched.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Helpers. water_stations has no public SELECT policy (the public reads
--    it through the public_stations view), so an RLS policy that queries
--    water_stations directly sees nothing for an anonymous visitor. These
--    run as definer and answer one yes/no question each.
-- ---------------------------------------------------------------------
create or replace function catalog_station_is_public(p_station_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from water_stations
    where id = p_station_id and is_colorum_verified and is_active
  );
$$;

create or replace function catalog_caller_owns_station(p_station_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from water_stations
    where id = p_station_id and owner_profile_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------
-- 1. Containers the association recognises.
-- ---------------------------------------------------------------------
create table if not exists container_types (
  code text primary key,
  label text not null,
  volume_ml integer not null check (volume_ml > 0),
  is_returnable boolean not null default false,
  -- Only containers the jug clearinghouse tracks map to its enum.
  ledger_jug_type jug_type,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint container_types_ledger_requires_returnable
    check (ledger_jug_type is null or is_returnable)
);

insert into container_types (code, label, volume_ml, is_returnable, ledger_jug_type, sort_order) values
  ('slim_5gal',    'Slim 5-gal',    18927, true,  'slim_5gal',  10),
  ('round_5gal',   'Round 5-gal',   18927, true,  'round_5gal', 20),
  ('gallon_1',     '1-gallon',       3785, false, null,         30),
  ('bottle_500ml', '500 mL bottle',   500, false, null,         40),
  ('bottle_350ml', '350 mL bottle',   350, false, null,         50)
on conflict (code) do nothing;

alter table container_types enable row level security;
drop policy if exists container_types_public_read on container_types;
create policy container_types_public_read on container_types for select using (true);
drop policy if exists container_types_admin_write on container_types;
create policy container_types_admin_write on container_types for all
  using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- 2. What each station sells, at what price.
-- ---------------------------------------------------------------------
create table if not exists station_products (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  water_type text not null check (water_type in ('purified', 'mineral', 'alkaline', 'distilled')),
  container_code text not null references container_types(code),
  kind text not null default 'refill' check (kind in ('refill', 'new_container')),
  price numeric(10,2) not null check (price > 0),
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (station_id, water_type, container_code, kind)
);
create index if not exists station_products_station_idx on station_products (station_id);

alter table station_products enable row level security;
drop policy if exists station_products_public_read on station_products;
create policy station_products_public_read on station_products for select
  using (catalog_station_is_public(station_id));
drop policy if exists station_products_owner_all on station_products;
create policy station_products_owner_all on station_products for all
  using (auth_has_role('station_owner') and catalog_caller_owns_station(station_id))
  with check (auth_has_role('station_owner') and catalog_caller_owns_station(station_id));
drop policy if exists station_products_admin_all on station_products;
create policy station_products_admin_all on station_products for all
  using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

create or replace function station_products_touch_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;
drop trigger if exists trg_station_products_touch_updated_at on station_products;
create trigger trg_station_products_touch_updated_at
  before update on station_products
  for each row execute function station_products_touch_updated_at();

-- ---------------------------------------------------------------------
-- 3. Floor prices become water type x container, applied to refills.
--    The table is empty (the previous patch cleared the test values), so
--    the container can be required outright. Any row without one can't be
--    interpreted under the new rule and is removed.
-- ---------------------------------------------------------------------
alter table floor_prices add column if not exists container_code text references container_types(code);
delete from floor_prices where container_code is null;
alter table floor_prices alter column container_code set not null;
alter table floor_prices drop constraint if exists floor_prices_association_id_water_type_key;
alter table floor_prices drop constraint if exists floor_prices_association_water_container_key;
alter table floor_prices add constraint floor_prices_association_water_container_key
  unique (association_id, water_type, container_code);

create or replace function enforce_product_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
  v_label text;
begin
  if new.kind <> 'refill' then
    return new;  -- floors regulate refills; a new container's price includes the container
  end if;
  -- Only when something the floor depends on changed -- the same trap the
  -- station-level trigger fell into (see patch_server_side_pricing.sql).
  if tg_op = 'UPDATE'
     and new.price is not distinct from old.price
     and new.water_type is not distinct from old.water_type
     and new.container_code is not distinct from old.container_code
     and new.kind is not distinct from old.kind then
    return new;
  end if;

  select fp.min_price_per_jug into v_floor
    from floor_prices fp
    join water_stations ws on ws.association_id = fp.association_id
    where ws.id = new.station_id
      and fp.water_type = new.water_type
      and fp.container_code = new.container_code;

  if v_floor is not null and new.price < v_floor then
    select label into v_label from container_types where code = new.container_code;
    raise exception '% % refills must be at least ₱% (the association''s floor price).',
      initcap(new.water_type), coalesce(v_label, new.container_code), v_floor;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_enforce_product_floor_price on station_products;
create trigger trg_enforce_product_floor_price
  before insert or update on station_products
  for each row execute function enforce_product_floor_price();

-- The single-price station floor no longer applies.
drop trigger if exists trg_enforce_floor_price on water_stations;
drop function if exists enforce_floor_price();

-- ---------------------------------------------------------------------
-- 4. Derived station columns, kept in step with available products.
-- ---------------------------------------------------------------------
create or replace function sync_station_from_products(p_station_id uuid) returns void as $$
begin
  update water_stations ws set
    offered_water_types = coalesce((
      select array_agg(distinct sp.water_type order by sp.water_type)
      from station_products sp
      where sp.station_id = p_station_id and sp.is_available
    ), '{}'),
    -- Only containers the jug ledger tracks belong in this enum array.
    offered_jug_types = coalesce((
      select array_agg(distinct ct.ledger_jug_type order by ct.ledger_jug_type)
      from station_products sp
      join container_types ct on ct.code = sp.container_code
      where sp.station_id = p_station_id and sp.is_available and ct.ledger_jug_type is not null
    ), '{}'),
    -- "From" price for listings: cheapest returnable refill (the 5-gallon
    -- price people compare), else cheapest product, else 0.
    price_per_jug = coalesce(
      (select min(sp.price) from station_products sp
         join container_types ct on ct.code = sp.container_code
        where sp.station_id = p_station_id and sp.is_available
          and sp.kind = 'refill' and ct.is_returnable),
      (select min(sp.price) from station_products sp
        where sp.station_id = p_station_id and sp.is_available),
      0)
  where ws.id = p_station_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function station_products_sync_station() returns trigger as $$
begin
  if tg_op = 'DELETE' then
    perform sync_station_from_products(old.station_id);
  else
    perform sync_station_from_products(new.station_id);
    if tg_op = 'UPDATE' and old.station_id is distinct from new.station_id then
      perform sync_station_from_products(old.station_id);
    end if;
  end if;
  return null;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_station_products_sync_station on station_products;
create trigger trg_station_products_sync_station
  after insert or update or delete on station_products
  for each row execute function station_products_sync_station();

-- Editing a container (e.g. retiring it, or changing what the ledger
-- tracks) changes what every station selling it should advertise.
create or replace function container_types_sync_stations() returns trigger as $$
declare
  r record;
begin
  for r in select distinct station_id from station_products where container_code = new.code loop
    perform sync_station_from_products(r.station_id);
  end loop;
  return null;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_container_types_sync_stations on container_types;
create trigger trg_container_types_sync_stations
  after update on container_types
  for each row execute function container_types_sync_stations();

-- ---------------------------------------------------------------------
-- 5. Orders remember exactly what was bought and for how much, so a later
--    price change never rewrites a past order.
-- ---------------------------------------------------------------------
alter table orders add column if not exists product_id uuid references station_products(id) on delete set null;
alter table orders add column if not exists unit_price numeric(10,2);
alter table orders add column if not exists product_kind text
  check (product_kind in ('refill', 'new_container'));

-- ---------------------------------------------------------------------
-- 6. insert_quick_order priced from the product.
--    DROP + CREATE, never CREATE OR REPLACE with an added parameter: that
--    creates a second overload and makes existing calls ambiguous -- the
--    failure set_order_status hit earlier in this project.
-- ---------------------------------------------------------------------
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz, text, uuid);

create function insert_quick_order(
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
  -- Default ceiling per order; for the association to confirm.
  v_max_qty constant integer := 50;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
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
    -- Older app builds send water type + container instead of a product.
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

  -- An exchanged empty only exists for refills of returnable containers.
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
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p.water_type, p.container_code,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin, p.id, p.price, p.kind
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 7. Drivers can't change what was bought or its price either.
-- ---------------------------------------------------------------------
create or replace function protect_order_financial_fields() returns trigger as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    if new.subtotal is distinct from old.subtotal
       or new.delivery_fee is distinct from old.delivery_fee
       or new.total_amount is distinct from old.total_amount
       or new.jugs_ordered is distinct from old.jugs_ordered
       or new.station_id is distinct from old.station_id
       or new.driver_worker_id is distinct from old.driver_worker_id
       or new.unit_price is distinct from old.unit_price
       or new.product_id is distinct from old.product_id
       or new.product_kind is distinct from old.product_kind
       or new.water_type is distinct from old.water_type
       or new.jug_type is distinct from old.jug_type then
      raise exception 'Drivers may not modify order financial, product, station, or assignment details.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 8. Jug-ledger entries only for refills: buying a new container involves
--    no empty jug, so nothing crosses station lines. Same signature as the
--    live function, so this is a true replacement.
-- ---------------------------------------------------------------------
create or replace function set_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_driver_worker_id uuid default null,
  p_guest_phone text default null,
  p_empty_jugs_returned integer default null,
  p_payment_collected boolean default null,
  p_jug_exchange_origin_station_id uuid default null,
  p_no_jug_exchange boolean default false
) returns void as $$
declare
  o orders%rowtype;
  v_caller_worker_id uuid;
  v_is_owner_or_admin boolean;
  v_new_driver_station_id uuid;
  v_new_driver_clearance clearance_status;
begin
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  v_is_owner_or_admin := auth_has_role('wasa_admin')
    or exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid());

  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  if v_is_owner_or_admin then
    if o.status = 'pending' and p_new_status = 'assigned' then
      if p_driver_worker_id is null then
        raise exception 'A driver must be specified to assign this order.';
      end if;
      select station_id, clearance_status into v_new_driver_station_id, v_new_driver_clearance
        from workers where id = p_driver_worker_id;
      if v_new_driver_station_id is null or v_new_driver_station_id <> o.station_id then
        raise exception 'That driver does not belong to this station.';
      end if;
      if v_new_driver_clearance = 'flagged' then
        raise exception 'This driver is flagged and cannot be assigned deliveries.';
      end if;
      update orders set status = 'assigned', driver_worker_id = p_driver_worker_id where id = p_order_id;
      return;
    elsif o.status in ('pending', 'assigned') and p_new_status = 'cancelled' then
      update orders set status = 'cancelled' where id = p_order_id;
      return;
    elsif o.status = 'assigned' and p_new_status = 'pending' then
      update orders set status = 'pending', driver_worker_id = null where id = p_order_id;
      return;
    else
      raise exception 'Not a valid status change for a station owner.';
    end if;
  end if;

  select id into v_caller_worker_id from workers where profile_id = auth.uid();
  if v_caller_worker_id is not null and o.driver_worker_id = v_caller_worker_id then
    if o.status = 'assigned' and p_new_status = 'active' then
      update orders set status = 'active' where id = p_order_id;
      return;
    elsif o.status in ('assigned', 'active') and p_new_status = 'done' then
      update orders set
        status = 'done',
        empty_jugs_returned = coalesce(p_empty_jugs_returned, empty_jugs_returned),
        payment_collected = coalesce(p_payment_collected, payment_collected),
        jug_exchange_origin_station_id = case
          when p_no_jug_exchange then null
          else coalesce(p_jug_exchange_origin_station_id, jug_exchange_origin_station_id)
        end
      where id = p_order_id
      returning * into o;

      if o.jug_exchange_origin_station_id is not null
         and o.jug_exchange_origin_station_id <> o.station_id
         and o.jug_type in ('slim_5gal', 'round_5gal')
         and coalesce(o.product_kind, 'refill') = 'refill'
         and coalesce(o.empty_jugs_returned, 0) > 0 then
        insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, related_order_id)
          values (o.station_id, o.jug_exchange_origin_station_id, o.jug_type::jug_type, o.empty_jugs_returned, o.id);
      end if;

      return;
    else
      raise exception 'Not a valid status change for a driver.';
    end if;
  end if;

  raise exception 'Not authorized to change this order.';
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 9. Order summaries carry the container's name and the kind of purchase,
--    so screens can say "3 x 500 mL bottle (new)" instead of "3 jugs".
--    Return types change, hence drop + create. Extra columns are ignored by
--    older app builds.
-- ---------------------------------------------------------------------
drop function if exists lookup_guest_order(uuid, text);
create function lookup_guest_order(p_order_id uuid, p_guest_phone text)
returns table (
  id uuid, station_name text, status order_status, jugs_ordered integer,
  water_type text, jug_type text, total_amount numeric, created_at timestamptz,
  container_label text, product_kind text, unit_price numeric
) as $$
begin
  return query
    select o.id, s.station_name, o.status, o.jugs_ordered, o.water_type, o.jug_type,
           o.total_amount, o.created_at, ct.label, o.product_kind, o.unit_price
    from orders o
    join water_stations s on s.id = o.station_id
    left join container_types ct on ct.code = o.jug_type
    where o.id = p_order_id and o.guest_phone = p_guest_phone;
end;
$$ language plpgsql security definer set search_path = public;

drop function if exists get_active_orders(uuid);
create function get_active_orders(p_station_id uuid)
returns table (
  id uuid, lat double precision, lng double precision, jugs_ordered integer,
  water_type text, jug_type text, container_label text, product_kind text,
  is_returnable boolean
) as $$
  select o.id,
         st_y(o.delivery_location::geometry) as lat,
         st_x(o.delivery_location::geometry) as lng,
         o.jugs_ordered,
         o.water_type,
         o.jug_type,
         ct.label,
         o.product_kind,
         coalesce(ct.is_returnable, o.jug_type in ('slim_5gal', 'round_5gal'))
  from orders o
  left join container_types ct on ct.code = o.jug_type
  where o.station_id = p_station_id
    and o.status in ('assigned', 'active');
$$ language sql stable;

-- ---------------------------------------------------------------------
-- 10. Migrate existing prices into products: every priced station gets a
--     refill product per offered water type x offered container, at its
--     current price. Unpriced stations get none -- they stay un-orderable
--     until the owner lists products, rather than being sold at P0.
-- ---------------------------------------------------------------------
insert into station_products (station_id, water_type, container_code, kind, price)
select ws.id, wt, jt, 'refill', ws.price_per_jug
from water_stations ws
cross join lateral unnest(ws.offered_water_types) as wt
cross join lateral unnest(
  case when cardinality(ws.offered_jug_types) > 0
       then ws.offered_jug_types::text[]
       else array['slim_5gal'] end
) as jt
where ws.price_per_jug > 0
  and wt in ('purified', 'mineral', 'alkaline', 'distilled')
on conflict (station_id, water_type, container_code, kind) do nothing;

-- Bring every station's derived columns in line with its products.
do $$
declare
  r record;
begin
  for r in select id from water_stations loop
    perform sync_station_from_products(r.id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 11. Owners now set their own delivery fee (Products screen), so the
--     server refuses a negative one rather than trusting the app to.
-- ---------------------------------------------------------------------
alter table water_stations drop constraint if exists water_stations_delivery_fee_nonnegative;
alter table water_stations add constraint water_stations_delivery_fee_nonnegative check (delivery_fee >= 0);
