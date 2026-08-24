-- =====================================================================
-- Incremental patch: customer accounts (fixes device-local-only guest
-- order tracking) + admin station deactivation & user suspension.
-- Additive/corrective to your existing schema -- no data loss. Paste into
-- the Supabase SQL Editor and run once. Safe to re-run.
--
--   1. register_customer() RPC -- lets a resident self-register a real
--      account (role 'public_consumer') so their orders and history are
--      tied to an account instead of device-local SharedPreferences.
--   2. water_stations.is_active -- admin-only deactivation switch,
--      reversible, hides a station from public_stations/ordering without
--      deleting any of its history.
--   3. insert_quick_order() now blocks placing an order against a
--      deactivated station, and had to move from security invoker to
--      security definer to be able to check is_active for every caller
--      (there's no RLS SELECT policy granting arbitrary/anon read access
--      to water_stations directly, only via the public_stations view).
--   4. prevent_owner_self_accreditation() trigger extended to also guard
--      is_active -- only WASA admin may deactivate/reactivate a station.
--   5. stations_owner_select/update/delete RLS tightened to also require
--      an active station_owner membership, not just ownership -- closes a
--      gap where a suspended owner could still manage their own station
--      directly even though every RPC-gated action already locked them out.
--   6. public_stations view now also filters is_active = true.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. register_customer RPC
-- ---------------------------------------------------------------------
create or replace function register_customer(p_full_name text) returns void as $$
declare
  v_association_id uuid;
begin
  if exists (select 1 from memberships where profile_id = auth.uid()) then
    return;
  end if;

  select id into v_association_id from associations limit 1;
  if v_association_id is null then
    raise exception 'No association configured.';
  end if;

  insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'public_consumer', null);
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 2. water_stations.is_active
-- ---------------------------------------------------------------------
alter table water_stations add column if not exists is_active boolean not null default true;

-- ---------------------------------------------------------------------
-- 3. insert_quick_order: active-station guard + security definer
-- ---------------------------------------------------------------------
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
  p_guest_phone text default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
begin
  select is_active into v_is_active from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active then
    raise exception 'This station is not currently accepting orders.';
  end if;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type,
    subtotal, delivery_fee, total_amount, customer_phone
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type,
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 4. prevent_owner_self_accreditation: also guard is_active
-- ---------------------------------------------------------------------
create or replace function prevent_owner_self_accreditation() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.is_accredited is distinct from old.is_accredited
       or new.accreditation_status is distinct from old.accreditation_status
       or new.is_colorum_verified is distinct from old.is_colorum_verified
       or new.is_active is distinct from old.is_active then
      raise exception 'Only WASA admin may change accreditation, verification, or active status.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;
-- (trigger trg_prevent_owner_self_accreditation already points at this
-- function from the earlier audit-remediation patch -- no need to recreate it.)

-- ---------------------------------------------------------------------
-- 5. stations_owner_select/update/delete: require active membership too
-- ---------------------------------------------------------------------
drop policy if exists stations_owner_select on water_stations;
create policy stations_owner_select on water_stations for select
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));

drop policy if exists stations_owner_update on water_stations;
create policy stations_owner_update on water_stations for update
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'))
  with check (owner_profile_id = auth.uid() and auth_has_role('station_owner'));

drop policy if exists stations_owner_delete on water_stations;
create policy stations_owner_delete on water_stations for delete
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));

-- ---------------------------------------------------------------------
-- 6. public_stations view: also filter is_active
-- ---------------------------------------------------------------------
drop view if exists public_stations cascade;
create view public_stations as
  select id, station_name, station_address, latitude, longitude,
         price_per_jug, delivery_fee, offered_water_types, photo_url,
         is_colorum_verified, is_accredited
  from water_stations
  where is_colorum_verified = true and is_active = true;

grant select on public_stations to anon, authenticated;
