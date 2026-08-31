-- =====================================================================
-- Incremental patch: station availability visibility + jug/container
-- options ("what other services") for the mobile app's near-me/discovery
-- features. Additive/corrective -- no data loss. Paste into the Supabase
-- SQL Editor and run once. Safe to re-run.
-- =====================================================================

-- ---- Jug/container options ("services offered") ----
-- Reuses the existing jug_type enum from the clearinghouse feature
-- (supabase/reset_and_rebuild.sql, 0007_jug_clearinghouse.sql) rather than
-- inventing a new type.

alter table water_stations add column if not exists offered_jug_types jug_type[] not null default '{}';
alter table water_stations add column if not exists offers_jug_exchange boolean not null default false;

-- ---- Owner-controlled "open right now" toggle ----
-- Deliberately a NEW column, not a repurposing of is_active. is_active is
-- the WASA-admin-only enable/suspend flag guarded by
-- trg_prevent_owner_self_accreditation (a station owner is blocked from
-- ever changing it) -- reusing it for a routine "closed for lunch" toggle
-- would mean a suspended owner could just flip it back on themselves.

alter table water_stations add column if not exists accepts_new_orders boolean not null default true;

-- ---- Station availability visibility ----
-- public_stations previously filtered out inactive (closed) stations
-- entirely -- a closed station just vanished instead of showing as
-- closed. This re-includes them (still gated by is_colorum_verified) and
-- exposes is_active + accepts_new_orders so the app can show a "Currently
-- Closed" badge instead of an order failing server-side with no warning.

drop view if exists public_stations cascade;

create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, ws.is_active,
         ws.offered_jug_types, ws.offers_jug_exchange, ws.accepts_new_orders,
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
  where ws.is_colorum_verified = true;

grant select on public_stations to anon, authenticated;

-- ---- insert_quick_order now also checks accepts_new_orders ----
-- Same parameter signature as before (patch_tier1_tier2_features.sql), so
-- create or replace is sufficient -- no need to drop first.

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
  p_scheduled_for timestamptz default null
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
    delivery_location, jugs_ordered, water_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type,
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id, p_scheduled_for
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;
