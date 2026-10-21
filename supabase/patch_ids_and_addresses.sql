-- Station IDs and written addresses.
--
-- 1. Every station gets a permanent code, GW-STN-<year>-<nnnn>, like the
--    workers' GW-WRK codes: two stations (or two workers) can share a name,
--    and the code tells them apart.
-- 2. A map pin alone isn't enough to find a door. Stations, saved customer
--    addresses and orders now carry a written address too: house no. /
--    street / subdivision, barangay, city and an optional landmark. An
--    order keeps a copy of the address it was sent to, so editing a saved
--    address later never changes where a past order went.

-- 1. Station codes ----------------------------------------------------------
create sequence if not exists station_code_seq;

create or replace function generate_station_code()
returns text
language sql set search_path = public
as $$
  select 'GW-STN-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('station_code_seq')::text, 4, '0');
$$;

alter table water_stations add column if not exists station_code text;

-- Existing stations, oldest first, numbered from their creation year.
do $$
declare s record;
begin
  for s in select id, created_at from water_stations where station_code is null order by created_at loop
    update water_stations
       set station_code = 'GW-STN-' || to_char(s.created_at, 'YYYY') || '-' || lpad(nextval('station_code_seq')::text, 4, '0')
     where id = s.id;
  end loop;
end $$;

alter table water_stations alter column station_code set default generate_station_code();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'water_stations_station_code_key') then
    alter table water_stations add constraint water_stations_station_code_key unique (station_code);
  end if;
end $$;

-- The station's written-address columns, before the view below that
-- shows the landmark (section 2 repeats them harmlessly).
alter table water_stations add column if not exists street text;
alter table water_stations add column if not exists city text default 'General Trias';
alter table water_stations add column if not exists landmark text;

-- The public directory and pages show the code and the landmark. New
-- columns go at the end so the view keeps its existing ones.
create or replace view public_stations as
 SELECT ws.id,
    ws.station_name,
    ws.station_address,
    ws.latitude,
    ws.longitude,
    ws.price_per_jug,
    ws.delivery_fee,
    ws.offered_water_types,
    ws.photo_url,
    ws.is_colorum_verified,
    ws.is_accredited,
    ws.is_active,
    ws.offered_jug_types,
    ws.offers_jug_exchange,
    ws.accepts_new_orders,
    ws.operating_days,
    ws.opens_at,
    ws.closes_at,
    b.name AS barangay_name,
    COALESCE(r.avg_rating, 0::numeric) AS avg_rating,
    COALESCE(r.review_count, 0::bigint) AS review_count,
    ws.standing,
    ws.created_at AS member_since,
    ws.accredited_at,
    ( SELECT max(p.reviewed_at) AS max
           FROM permits p
          WHERE p.station_id = ws.id AND p.permit_type = 'water_quality_test_report'::permit_type AND p.status = 'approved'::permit_status) AS last_water_test_at,
    ( SELECT max(p.expiry_date) AS max
           FROM permits p
          WHERE p.station_id = ws.id AND p.permit_type = 'sanitary_permit'::permit_type AND p.status = 'approved'::permit_status) AS sanitary_valid_until,
    ws.station_code,
    ws.landmark
   FROM water_stations ws
     LEFT JOIN barangays b ON b.id = ws.barangay_id
     LEFT JOIN ( SELECT reviews.station_id,
            avg(reviews.rating)::numeric(3,2) AS avg_rating,
            count(*) AS review_count
           FROM reviews
          GROUP BY reviews.station_id) r ON r.station_id = ws.id
  WHERE ws.is_colorum_verified = true AND ws.is_active = true;

-- 2. Written addresses --------------------------------------------------------
alter table water_stations add column if not exists street text;
alter table water_stations add column if not exists city text default 'General Trias';
alter table water_stations add column if not exists landmark text;

alter table customer_addresses add column if not exists street text;
alter table customer_addresses add column if not exists barangay text;
alter table customer_addresses add column if not exists city text default 'General Trias';
alter table customer_addresses add column if not exists landmark text;

alter table orders add column if not exists delivery_address text;

-- Records the written address an order is delivered to. The customer can
-- set it on their own order while it is still pending; the station's owner
-- or staff can set or correct it until the order is done (phone orders).
-- Orders can't be written directly by members (direct-write guards), so
-- this is the way in.
create or replace function set_order_delivery_address(p_order_id uuid, p_address text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o orders%rowtype;
  v_address text := nullif(trim(p_address), '');
  v_allowed boolean;
begin
  select * into o from orders where id = p_order_id;
  if not found then
    raise exception 'Order not found.';
  end if;
  if v_address is not null and length(v_address) > 300 then
    raise exception 'Keep the address under 300 characters.';
  end if;
  -- coalesce: for someone who isn't staff, auth_staff_station_id() is NULL,
  -- which made the whole test NULL and "if not NULL" let anyone through.
  v_allowed := coalesce(
       (o.customer_profile_id = auth.uid() and o.status = 'pending')
    or (o.status not in ('done', 'cancelled') and (
          exists (select 1 from water_stations ws where ws.id = o.station_id and ws.owner_profile_id = auth.uid())
          or coalesce(o.station_id = auth_staff_station_id(), false))),
    false);
  if not v_allowed then
    raise exception 'You can''t change the address on this order.';
  end if;
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set delivery_address = v_address where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$;

revoke all on function set_order_delivery_address(uuid, text) from public, anon;
grant execute on function set_order_delivery_address(uuid, text) to authenticated;
