-- =====================================================================
-- AquaRoute / GENTRI WASA -- FULL RESET + REBUILD
-- =====================================================================
-- WARNING: this deletes ALL existing data in the tables listed below,
-- both the old single-tenant prototype schema (user_profiles,
-- water_stations, orders, driver_states) and any partially-applied new
-- schema. Only run this against a project you intend to wipe clean --
-- there is no undo once this runs. Auth users themselves (auth.users)
-- are NOT deleted; only app-level tables/policies/functions are.
--
-- Paste this whole file into the Supabase SQL Editor and run it once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DROP: storage policies only. Supabase blocks direct DELETE on
-- storage.objects/storage.buckets from SQL ("Direct deletion from storage
-- tables is not allowed. Use the Storage API instead.") -- if you've
-- actually uploaded test permit documents and want them gone, clear them
-- from the Dashboard (Storage -> permit-documents -> select all -> Delete)
-- before running this script. The bucket-creation step further down uses
-- `on conflict (id) do nothing`, so a pre-existing bucket is left alone
-- harmlessly either way.
-- ---------------------------------------------------------------------
drop policy if exists permit_docs_owner_all on storage.objects;
drop policy if exists permit_docs_admin_read on storage.objects;
drop policy if exists worker_credentials_self_all on storage.objects;
drop policy if exists worker_credentials_admin_read on storage.objects;
drop policy if exists avatars_self_write on storage.objects;
drop policy if exists station_photos_owner_write on storage.objects;
drop policy if exists bulletin_images_poster_write on storage.objects;

-- ---------------------------------------------------------------------
-- 2. DROP: views
-- ---------------------------------------------------------------------
drop view if exists public_stations cascade;
drop view if exists jug_balances cascade;
drop view if exists bulletin_reaction_counts cascade;

-- ---------------------------------------------------------------------
-- 3. DROP: tables (new schema + any leftover old prototype tables),
--    children before parents, all with cascade for safety.
-- ---------------------------------------------------------------------
drop table if exists bulletin_reactions cascade;
drop table if exists bulletins cascade;
drop table if exists floor_prices cascade;
drop table if exists jug_settlements cascade;
drop table if exists jug_ledger_entries cascade;
drop table if exists driver_states cascade;
drop table if exists orders cascade;
drop table if exists worker_incidents cascade;
drop table if exists worker_credentials cascade;
drop table if exists worker_station_history cascade;
drop table if exists workers cascade;
drop table if exists permits cascade;
drop table if exists memberships cascade;
drop table if exists water_stations cascade;
drop table if exists barangays cascade;
drop table if exists profiles cascade;
drop table if exists associations cascade;
-- Old single-tenant prototype table, if it still exists:
drop table if exists user_profiles cascade;

-- ---------------------------------------------------------------------
-- 4. DROP: trigger on auth.users, then functions, then types/sequence
-- ---------------------------------------------------------------------
drop trigger if exists trg_handle_new_auth_user on auth.users;

drop function if exists handle_new_auth_user() cascade;
drop function if exists auth_has_role(app_role) cascade;
drop function if exists auth_station_id() cascade;
drop function if exists sync_required_permits() cascade;
drop function if exists recompute_accreditation() cascade;
drop function if exists generate_worker_code() cascade;
drop function if exists flag_on_incident_filed() cascade;
drop function if exists apply_incident_resolution() cascade;
drop function if exists get_active_orders(uuid) cascade;
drop function if exists insert_quick_order(uuid, double precision, double precision, int, text, numeric, numeric, numeric, text, text) cascade;
drop function if exists insert_quick_order(uuid, double precision, double precision, int, text, numeric, numeric, numeric, text, text, text) cascade;
drop function if exists confirm_jug_settlement(uuid) cascade;
drop function if exists reject_jug_settlement(uuid) cascade;
drop function if exists sync_required_worker_credentials() cascade;
drop function if exists recompute_worker_clearance() cascade;
drop function if exists register_driver_for_station(text, text, text, text, int) cascade;
drop function if exists driver_switch_station(text) cascade;
drop function if exists driver_leave_station() cascade;
drop function if exists owner_remove_worker(uuid) cascade;
drop function if exists hire_check_search(text) cascade;
drop function if exists hire_check_station_history(uuid) cascade;
drop function if exists register_station_owner(text, text, text, double precision, double precision) cascade;
drop function if exists register_customer(text) cascade;
drop function if exists prevent_owner_self_accreditation() cascade;
drop function if exists prevent_owner_self_permit_approval() cascade;
drop function if exists prevent_worker_self_credential_approval() cascade;
drop function if exists protect_order_financial_fields() cascade;
drop function if exists validate_bulletin_author() cascade;
drop function if exists enforce_floor_price() cascade;
drop function if exists lookup_guest_order(uuid, text) cascade;

drop sequence if exists worker_code_seq cascade;

drop type if exists app_role cascade;
drop type if exists permit_type cascade;
drop type if exists permit_status cascade;
drop type if exists clearance_status cascade;
drop type if exists incident_status cascade;
drop type if exists station_history_status cascade;
drop type if exists worker_credential_type cascade;
drop type if exists order_status cascade;
drop type if exists jug_type cascade;
drop type if exists settlement_status cascade;
drop type if exists bulletin_category cascade;

-- =====================================================================
-- REBUILD -- everything below is 0001_core_identity.sql .. 0010_seed_gentri_wasa.sql
-- concatenated in order.
-- =====================================================================

-- ---- 0001_core_identity.sql ----

create extension if not exists pgcrypto;
create extension if not exists postgis;

create table associations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  province text not null default 'Cavite',
  municipality text not null default 'General Trias',
  created_at timestamptz not null default now()
);

create table barangays (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (association_id, name)
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone_number text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create type app_role as enum ('wasa_admin', 'station_owner', 'driver', 'public_consumer');

create or replace function handle_new_auth_user() returns trigger as $$
begin
  insert into profiles (id, full_name, phone_number)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'phone_number')
    on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_handle_new_auth_user
  after insert on auth.users
  for each row execute function handle_new_auth_user();

insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

-- ---- 0002_stations.sql ----

create table water_stations (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  owner_profile_id uuid not null references profiles(id),
  barangay_id uuid references barangays(id),
  invite_code text not null unique,
  station_name text not null,
  station_address text not null,
  latitude double precision not null,
  longitude double precision not null,
  price_per_jug numeric(10,2) not null default 0,
  delivery_fee numeric(10,2) not null default 0,
  photo_url text,
  offered_water_types text[] not null default '{}',
  is_colorum_verified boolean not null default false,
  is_accredited boolean not null default false,
  accreditation_status text not null default 'pending'
    check (accreditation_status in ('pending','under_review','accredited','rejected','suspended')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index water_stations_association_idx on water_stations (association_id);
create index water_stations_owner_idx on water_stations (owner_profile_id);
create index water_stations_barangay_idx on water_stations (barangay_id);

insert into storage.buckets (id, name, public)
  values ('station-photos', 'station-photos', true)
  on conflict (id) do nothing;

-- ---- 0003_memberships.sql ----

create table memberships (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  association_id uuid not null references associations(id),
  role app_role not null,
  station_id uuid references water_stations(id),
  status text not null default 'active' check (status in ('active','suspended','revoked')),
  created_at timestamptz not null default now(),
  unique (profile_id, association_id, role, station_id)
);

create index memberships_profile_idx on memberships (profile_id);
create index memberships_station_idx on memberships (station_id);

create or replace function auth_has_role(check_role app_role) returns boolean as $$
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid()
      and m.role = check_role
      and m.status = 'active'
  );
$$ language sql stable security definer set search_path = public;

create or replace function auth_station_id() returns uuid as $$
  select m.station_id from memberships m
  where m.profile_id = auth.uid()
    and m.role in ('station_owner', 'driver')
    and m.status = 'active'
  limit 1;
$$ language sql stable security definer set search_path = public;

create or replace function register_station_owner(
  p_station_name text,
  p_station_address text,
  p_invite_code text,
  p_latitude double precision,
  p_longitude double precision
) returns uuid as $$
declare
  v_association_id uuid;
  v_station_id uuid;
  v_existing_station_id uuid;
begin
  select station_id into v_existing_station_id from memberships
    where profile_id = auth.uid() and role = 'station_owner' limit 1;
  if v_existing_station_id is not null then
    return v_existing_station_id;
  end if;

  select id into v_association_id from associations limit 1;
  if v_association_id is null then
    raise exception 'No association configured.';
  end if;

  insert into water_stations (association_id, owner_profile_id, invite_code, station_name, station_address, latitude, longitude)
    values (v_association_id, auth.uid(), p_invite_code, p_station_name, p_station_address, p_latitude, p_longitude)
    returning id into v_station_id;

  insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'station_owner', v_station_id);

  return v_station_id;
end;
$$ language plpgsql security definer set search_path = public;

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

-- ---- 0004_permits.sql ----

create type permit_type as enum (
  'business_permit',
  'sanitary_permit',
  'fda_license',
  'alkaline_tech_cert',
  'alkaline_water_test'
);

create type permit_status as enum ('missing', 'pending_review', 'approved', 'rejected');

create table permits (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  permit_type permit_type not null,
  is_required boolean not null default true,
  storage_path text,
  status permit_status not null default 'missing',
  reviewed_by uuid references profiles(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  expiry_date date,
  uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (station_id, permit_type)
);

create index permits_station_idx on permits (station_id);
create index permits_status_idx on permits (status);

create or replace function sync_required_permits() returns trigger as $$
begin
  insert into permits (station_id, permit_type, is_required)
    values
      (new.id, 'business_permit', true),
      (new.id, 'sanitary_permit', true)
    on conflict (station_id, permit_type) do nothing;

  if 'alkaline' = any(new.offered_water_types) then
    insert into permits (station_id, permit_type, is_required)
      values
        (new.id, 'alkaline_tech_cert', true),
        (new.id, 'alkaline_water_test', true)
      on conflict (station_id, permit_type) do update set is_required = true;
  else
    update permits set is_required = false
      where station_id = new.id
        and permit_type in ('alkaline_tech_cert', 'alkaline_water_test');
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_sync_required_permits
  after insert or update of offered_water_types on water_stations
  for each row execute function sync_required_permits();

create or replace function recompute_accreditation() returns trigger as $$
declare
  all_ok boolean;
begin
  select not exists (
    select 1 from permits
    where station_id = new.station_id
      and is_required = true
      and status <> 'approved'
  ) into all_ok;

  update water_stations
    set is_accredited = all_ok,
        accreditation_status = case
          when all_ok then 'accredited'
          when accreditation_status = 'accredited' then 'under_review'
          else accreditation_status
        end,
        updated_at = now()
    where id = new.station_id;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_recompute_accreditation
  after update of status on permits
  for each row execute function recompute_accreditation();

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

create trigger trg_prevent_owner_self_accreditation
  before update on water_stations
  for each row execute function prevent_owner_self_accreditation();

create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.status = 'approved'
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_prevent_owner_self_permit_approval
  before update on permits
  for each row execute function prevent_owner_self_permit_approval();

insert into storage.buckets (id, name, public)
  values ('permit-documents', 'permit-documents', false)
  on conflict (id) do nothing;

-- ---- 0005_workers.sql ----

create type clearance_status as enum ('pending_clearance', 'cleared', 'flagged');

create sequence worker_code_seq;

create or replace function generate_worker_code() returns text as $$
  select 'GW-WRK-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('worker_code_seq')::text, 4, '0');
$$ language sql;

create table workers (
  id uuid primary key default gen_random_uuid(),
  station_id uuid references water_stations(id) on delete set null,
  profile_id uuid references profiles(id),
  worker_code text not null unique default generate_worker_code(),
  full_name text not null,
  role_title text not null default 'driver/helper',
  phone_number text,
  vehicle_plate text,
  jug_capacity int,
  clearance_status clearance_status not null default 'pending_clearance',
  qr_payload text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workers_station_idx on workers (station_id);
create index workers_profile_idx on workers (profile_id);
create unique index workers_profile_unique_active on workers (profile_id) where profile_id is not null;

create type incident_status as enum ('pending_review', 'confirmed_flag', 'dismissed');

create table worker_incidents (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  reported_by_profile_id uuid not null references profiles(id),
  incident_type text not null,
  description text not null,
  amount_involved numeric(10,2),
  status incident_status not null default 'pending_review',
  resolved_by uuid references profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index worker_incidents_worker_idx on worker_incidents (worker_id);

create or replace function flag_on_incident_filed() returns trigger as $$
begin
  update workers set clearance_status = 'pending_clearance', updated_at = now()
    where id = new.worker_id and clearance_status = 'cleared';
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_incident_filed
  after insert on worker_incidents
  for each row execute function flag_on_incident_filed();

create or replace function apply_incident_resolution() returns trigger as $$
begin
  if new.status = 'confirmed_flag' and old.status <> 'confirmed_flag' then
    update workers set clearance_status = 'flagged', updated_at = now() where id = new.worker_id;
  elsif new.status = 'dismissed' and old.status <> 'dismissed' then
    if not exists (
      select 1 from worker_incidents
      where worker_id = new.worker_id and status = 'confirmed_flag' and id <> new.id
    ) then
      update workers set clearance_status = 'cleared', updated_at = now() where id = new.worker_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_incident_resolution
  after update of status on worker_incidents
  for each row execute function apply_incident_resolution();

create type station_history_status as enum ('active', 'left', 'removed');

create table worker_station_history (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  station_id uuid not null references water_stations(id),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  status station_history_status not null default 'active',
  ended_by_profile_id uuid references profiles(id)
);

create index worker_station_history_worker_idx on worker_station_history (worker_id);
create index worker_station_history_station_idx on worker_station_history (station_id);
create unique index worker_station_history_one_active on worker_station_history (worker_id) where status = 'active';

create type worker_credential_type as enum ('government_id', 'drivers_license');

create table worker_credentials (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  credential_type worker_credential_type not null,
  storage_path text,
  status permit_status not null default 'missing',
  reviewed_by uuid references profiles(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (worker_id, credential_type)
);

create index worker_credentials_worker_idx on worker_credentials (worker_id);
create index worker_credentials_status_idx on worker_credentials (status);

create or replace function sync_required_worker_credentials() returns trigger as $$
begin
  insert into worker_credentials (worker_id, credential_type)
    values (new.id, 'government_id'), (new.id, 'drivers_license')
    on conflict (worker_id, credential_type) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_sync_required_worker_credentials
  after insert on workers
  for each row execute function sync_required_worker_credentials();

create or replace function recompute_worker_clearance() returns trigger as $$
declare all_ok boolean;
begin
  select not exists (
    select 1 from worker_credentials where worker_id = new.worker_id and status <> 'approved'
  ) into all_ok;

  if all_ok and not exists (
    select 1 from worker_incidents where worker_id = new.worker_id and status = 'pending_review'
  ) then
    update workers set clearance_status = 'cleared', updated_at = now()
      where id = new.worker_id and clearance_status = 'pending_clearance';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_recompute_worker_clearance
  after update of status on worker_credentials
  for each row execute function recompute_worker_clearance();

create or replace function prevent_worker_self_credential_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.status = 'approved'
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a credential.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_prevent_worker_self_credential_approval
  before update on worker_credentials
  for each row execute function prevent_worker_self_credential_approval();

insert into storage.buckets (id, name, public)
  values ('worker-credentials', 'worker-credentials', false)
  on conflict (id) do nothing;

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

create or replace function driver_switch_station(p_invite_code text) returns void as $$
declare
  v_worker_id uuid;
  v_clearance clearance_status;
  v_new_station_id uuid;
  v_association_id uuid;
begin
  select id, clearance_status into v_worker_id, v_clearance from workers where profile_id = auth.uid();

  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;

  if v_clearance = 'flagged' then
    raise exception 'Cannot switch stations while flagged. Contact WASA to resolve outstanding incidents.';
  end if;

  select id, association_id into v_new_station_id, v_association_id
    from water_stations where invite_code ilike p_invite_code;

  if v_new_station_id is null then
    raise exception 'Invalid station invite code.';
  end if;

  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';

  update workers set station_id = v_new_station_id, updated_at = now() where id = v_worker_id;

  update memberships set station_id = v_new_station_id, association_id = v_association_id
    where profile_id = auth.uid() and role = 'driver';

  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_new_station_id);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function driver_leave_station() returns void as $$
declare v_worker_id uuid;
begin
  select id into v_worker_id from workers where profile_id = auth.uid();

  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;

  update workers set station_id = null, updated_at = now() where id = v_worker_id;
  update memberships set station_id = null where profile_id = auth.uid() and role = 'driver';
  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function owner_remove_worker(p_worker_id uuid) returns void as $$
declare
  v_station_id uuid;
  v_profile_id uuid;
begin
  select station_id, profile_id into v_station_id, v_profile_id from workers where id = p_worker_id;

  if v_station_id is null or auth_station_id() is null or v_station_id <> auth_station_id() then
    raise exception 'Not authorized to remove this worker.';
  end if;

  update workers set station_id = null, updated_at = now() where id = p_worker_id;
  if v_profile_id is not null then
    update memberships set station_id = null where profile_id = v_profile_id and role = 'driver';
  end if;
  update worker_station_history set status = 'removed', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = p_worker_id and status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function hire_check_search(p_query text)
returns table (worker_id uuid, worker_code text, full_name text, clearance_status clearance_status, confirmed_incident_count bigint) as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    raise exception 'Not authorized.';
  end if;

  return query
    select w.id, w.worker_code, w.full_name, w.clearance_status,
      (select count(*) from worker_incidents wi where wi.worker_id = w.id and wi.status = 'confirmed_flag')
    from workers w
    where w.full_name ilike '%' || p_query || '%' or w.worker_code ilike '%' || p_query || '%';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function hire_check_station_history(p_worker_id uuid)
returns table (station_name text, joined_at timestamptz, left_at timestamptz, status station_history_status) as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    raise exception 'Not authorized.';
  end if;

  return query
    select s.station_name, h.joined_at, h.left_at, h.status
    from worker_station_history h
    join water_stations s on s.id = h.station_id
    where h.worker_id = p_worker_id
    order by h.joined_at desc;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- 0006_orders_driver_state.sql ----

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
  client_request_id text,
  scheduled_for timestamptz,
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
  is_active boolean not null default false,
  last_updated timestamptz not null default now()
);

create index driver_states_station_idx on driver_states (station_id);

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

create or replace function get_active_delivery_driver(p_order_id uuid, p_guest_phone text default null)
returns table (
  driver_name text,
  driver_phone text,
  lat double precision,
  lng double precision,
  last_updated timestamptz
) as $$
declare
  v_order orders%rowtype;
begin
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found.';
  end if;

  if not (
    (auth.uid() is not null and v_order.customer_profile_id = auth.uid())
    or (p_guest_phone is not null and v_order.guest_phone = p_guest_phone)
  ) then
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

-- ---- 0007_jug_clearinghouse.sql ----

create type jug_type as enum ('slim_5gal', 'round_5gal');

create table jug_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  holder_station_id uuid not null references water_stations(id),
  owner_station_id uuid not null references water_stations(id),
  jug_type jug_type not null,
  quantity int not null check (quantity <> 0),
  related_order_id uuid references orders(id),
  recorded_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  check (holder_station_id <> owner_station_id)
);

create index jug_ledger_holder_idx on jug_ledger_entries (holder_station_id);
create index jug_ledger_owner_idx on jug_ledger_entries (owner_station_id);

create view jug_balances as
  select holder_station_id, owner_station_id, jug_type, sum(quantity) as net_qty
  from jug_ledger_entries
  group by holder_station_id, owner_station_id, jug_type
  having sum(quantity) <> 0;

create type settlement_status as enum ('proposed', 'confirmed', 'rejected');

create table jug_settlements (
  id uuid primary key default gen_random_uuid(),
  holder_station_id uuid not null references water_stations(id),
  owner_station_id uuid not null references water_stations(id),
  jug_type jug_type not null,
  quantity int not null check (quantity > 0),
  status settlement_status not null default 'proposed',
  proposed_by uuid not null references profiles(id),
  confirmed_by uuid references profiles(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index jug_settlements_holder_idx on jug_settlements (holder_station_id);
create index jug_settlements_owner_idx on jug_settlements (owner_station_id);

create or replace function confirm_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if auth_station_id() is null or auth_station_id() <> s.owner_station_id then
    raise exception 'only the owning/receiving station may confirm this settlement';
  end if;

  insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by)
    values (s.holder_station_id, s.owner_station_id, s.jug_type, -s.quantity, auth.uid());

  update jug_settlements
    set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function reject_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if (auth_station_id() is null or auth_station_id() <> s.owner_station_id) and not auth_has_role('wasa_admin') then
    raise exception 'only the owning/receiving station or a WASA admin may reject this settlement';
  end if;

  update jug_settlements set status = 'rejected' where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- 0008_bulletin.sql ----

create table floor_prices (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  water_type text not null,
  min_price_per_jug numeric(10,2) not null,
  effective_date date not null default current_date,
  set_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  unique (association_id, water_type)
);

create index floor_prices_association_idx on floor_prices (association_id);

create type bulletin_category as enum ('announcement', 'price_change', 'event', 'discussion');

create table bulletins (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  category bulletin_category not null default 'discussion',
  title text not null,
  body text not null,
  is_pinned boolean not null default false,
  posted_by uuid not null references profiles(id),
  author_name text not null,
  author_role app_role not null,
  author_station_name text,
  image_url text,
  created_at timestamptz not null default now()
);

create index bulletins_association_idx on bulletins (association_id);
create index bulletins_category_idx on bulletins (category);

create table bulletin_reactions (
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bulletin_id, profile_id)
);

create index bulletin_reactions_bulletin_idx on bulletin_reactions (bulletin_id);

create view bulletin_reaction_counts as
  select bulletin_id, count(*) as reaction_count
  from bulletin_reactions
  group by bulletin_id;

grant select on bulletin_reaction_counts to anon, authenticated;

create table bulletin_comments (
  id uuid primary key default gen_random_uuid(),
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index bulletin_comments_bulletin_idx on bulletin_comments (bulletin_id);

insert into storage.buckets (id, name, public)
  values ('bulletin-images', 'bulletin-images', true)
  on conflict (id) do nothing;

create or replace function validate_bulletin_author() returns trigger as $$
begin
  if new.posted_by <> auth.uid() then
    raise exception 'posted_by must match the authenticated user.';
  end if;

  if not exists (
    select 1 from memberships
    where profile_id = auth.uid() and role = new.author_role and status = 'active'
  ) then
    raise exception 'author_role does not match an active membership for this account.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_validate_bulletin_author
  before insert on bulletins
  for each row execute function validate_bulletin_author();

create or replace function enforce_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
begin
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

create trigger trg_enforce_floor_price
  before insert or update of price_per_jug, offered_water_types on water_stations
  for each row execute function enforce_floor_price();

create or replace function lookup_guest_order(p_order_id uuid, p_guest_phone text)
returns table (
  id uuid, station_name text, status order_status, jugs_ordered int,
  water_type text, total_amount numeric, created_at timestamptz
) as $$
begin
  return query
    select o.id, s.station_name, o.status, o.jugs_ordered, o.water_type, o.total_amount, o.created_at
    from orders o
    join water_stations s on s.id = o.station_id
    where o.id = p_order_id and o.guest_phone = p_guest_phone;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- tier1_tier2_features.sql ----

create table reviews (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (station_id, profile_id)
);

create index reviews_station_idx on reviews (station_id);

create or replace function submit_station_review(p_station_id uuid, p_rating smallint, p_comment text default null)
returns uuid as $$
declare
  v_review_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to leave a review.';
  end if;

  if p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5.';
  end if;

  if not exists (
    select 1 from orders
    where customer_profile_id = auth.uid()
      and station_id = p_station_id
      and status = 'done'
  ) then
    raise exception 'You can only review a station after a completed delivery from them.';
  end if;

  insert into reviews (station_id, profile_id, rating, comment)
  values (p_station_id, auth.uid(), p_rating, p_comment)
  on conflict (station_id, profile_id) do update
    set rating = excluded.rating, comment = excluded.comment, created_at = now()
  returning id into v_review_id;

  return v_review_id;
end;
$$ language plpgsql security definer set search_path = public;

create table resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'general',
  storage_path text not null,
  file_url text not null,
  uploaded_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

insert into storage.buckets (id, name, public)
  values ('resources', 'resources', true)
  on conflict (id) do nothing;

create table events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date timestamptz not null,
  location text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

create index events_event_date_idx on events (event_date);

-- ---- 0009_rls.sql ----

alter table profiles enable row level security;
alter table memberships enable row level security;
alter table water_stations enable row level security;
alter table permits enable row level security;
alter table workers enable row level security;
alter table worker_incidents enable row level security;
alter table worker_station_history enable row level security;
alter table worker_credentials enable row level security;
alter table orders enable row level security;
alter table driver_states enable row level security;
alter table jug_ledger_entries enable row level security;
alter table jug_settlements enable row level security;
alter table floor_prices enable row level security;
alter table bulletins enable row level security;
alter table bulletin_reactions enable row level security;
alter table reviews enable row level security;
alter table resources enable row level security;
alter table events enable row level security;
alter table bulletin_comments enable row level security;

create policy profiles_self_read on profiles for select
  using (id = auth.uid());
create policy profiles_self_update on profiles for update
  using (id = auth.uid());
create policy profiles_admin_read on profiles for select
  using (auth_has_role('wasa_admin'));

create policy memberships_self_read on memberships for select
  using (profile_id = auth.uid());
create policy memberships_admin_all on memberships for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy stations_owner_select on water_stations for select
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_owner_update on water_stations for update
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'))
  with check (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_owner_delete on water_stations for delete
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_admin_all on water_stations for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));
create policy stations_driver_read on water_stations for select
  using (id = auth_station_id());

create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, b.name as barangay_name,
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

create policy reviews_public_read on reviews for select
  using (true);
create policy reviews_admin_all on reviews for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy resources_public_read on resources for select
  using (true);
create policy resources_admin_all on resources for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy events_public_read on events for select
  using (true);
create policy events_admin_all on events for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy permits_owner on permits for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy permits_admin on permits for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy workers_owner on workers for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy workers_self_read on workers for select
  using (profile_id = auth.uid());
create policy workers_admin on workers for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy incidents_owner_read on worker_incidents for select
  using (worker_id in (
    select w.id from workers w
    join water_stations s on s.id = w.station_id
    where s.owner_profile_id = auth.uid()
  ));
create policy incidents_owner_insert on worker_incidents for insert
  with check (
    reported_by_profile_id = auth.uid()
    and worker_id in (
      select w.id from workers w
      join water_stations s on s.id = w.station_id
      where s.owner_profile_id = auth.uid()
    )
  );
create policy incidents_admin_all on worker_incidents for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy history_self_read on worker_station_history for select
  using (worker_id in (select id from workers where profile_id = auth.uid()));
create policy history_current_owner_read on worker_station_history for select
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy history_admin_read on worker_station_history for select
  using (auth_has_role('wasa_admin'));

create policy worker_credentials_self on worker_credentials for all
  using (worker_id in (select id from workers where profile_id = auth.uid()))
  with check (worker_id in (select id from workers where profile_id = auth.uid()));
create policy worker_credentials_owner_read on worker_credentials for select
  using (worker_id in (
    select w.id from workers w
    join water_stations s on s.id = w.station_id
    where s.owner_profile_id = auth.uid()
  ));
create policy worker_credentials_admin on worker_credentials for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy orders_owner_all on orders for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy orders_driver_read on orders for select
  using (station_id = auth_station_id());
create policy orders_driver_update on orders for update
  using (station_id = auth_station_id());
create policy orders_customer_read on orders for select
  using (customer_profile_id = auth.uid());
create policy orders_public_insert on orders for insert
  with check (customer_profile_id is null and guest_name is not null);
create policy orders_authenticated_insert on orders for insert
  with check (customer_profile_id = auth.uid());
create policy orders_admin_read on orders for select
  using (auth_has_role('wasa_admin'));

create policy driver_states_self on driver_states for all
  using (worker_id in (select id from workers where profile_id = auth.uid()))
  with check (worker_id in (select id from workers where profile_id = auth.uid()));
create policy driver_states_owner_read on driver_states for select
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy driver_states_admin_read on driver_states for select
  using (auth_has_role('wasa_admin'));

create policy jug_ledger_involved_read on jug_ledger_entries for select
  using (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_ledger_involved_insert on jug_ledger_entries for insert
  with check (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_ledger_admin on jug_ledger_entries for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy jug_settlements_involved_read on jug_settlements for select
  using (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_settlements_propose on jug_settlements for insert
  with check (holder_station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy jug_settlements_admin on jug_settlements for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy bulletins_public_read on bulletins for select
  using (true);
create policy bulletins_admin_insert on bulletins for insert
  with check (auth_has_role('wasa_admin') and posted_by = auth.uid());
create policy bulletins_member_insert on bulletins for insert
  with check (
    category in ('event', 'discussion')
    and (auth_has_role('station_owner') or auth_has_role('driver'))
    and posted_by = auth.uid()
  );
create policy bulletins_admin_update on bulletins for update
  using (auth_has_role('wasa_admin'));
create policy bulletins_admin_delete on bulletins for delete
  using (auth_has_role('wasa_admin'));

create policy floor_prices_public_read on floor_prices for select
  using (true);
create policy floor_prices_admin_insert on floor_prices for insert
  with check (auth_has_role('wasa_admin'));
create policy floor_prices_admin_update on floor_prices for update
  using (auth_has_role('wasa_admin'));
create policy floor_prices_admin_delete on floor_prices for delete
  using (auth_has_role('wasa_admin'));

create policy bulletin_reactions_public_read on bulletin_reactions for select
  using (true);
create policy bulletin_reactions_self_insert on bulletin_reactions for insert
  with check (profile_id = auth.uid());
create policy bulletin_reactions_self_delete on bulletin_reactions for delete
  using (profile_id = auth.uid());

create policy bulletin_comments_public_read on bulletin_comments for select
  using (true);
create policy bulletin_comments_self_insert on bulletin_comments for insert
  with check (profile_id = auth.uid());
create policy bulletin_comments_self_or_admin_delete on bulletin_comments for delete
  using (profile_id = auth.uid() or auth_has_role('wasa_admin'));

create policy permit_docs_owner_all on storage.objects for all
  using (
    bucket_id = 'permit-documents'
    and (storage.foldername(name))[1]::uuid in (
      select id from water_stations where owner_profile_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'permit-documents'
    and (storage.foldername(name))[1]::uuid in (
      select id from water_stations where owner_profile_id = auth.uid()
    )
  );
create policy permit_docs_admin_read on storage.objects for select
  using (bucket_id = 'permit-documents' and auth_has_role('wasa_admin'));

create policy worker_credentials_self_all on storage.objects for all
  using (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (
      select id from workers where profile_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (
      select id from workers where profile_id = auth.uid()
    )
  );
create policy worker_credentials_admin_read on storage.objects for select
  using (bucket_id = 'worker-credentials' and auth_has_role('wasa_admin'));

create policy avatars_self_write on storage.objects for all
  using (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid())
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid());

create policy station_photos_owner_write on storage.objects for all
  using (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  )
  with check (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  );

create policy bulletin_images_poster_write on storage.objects for insert
  with check (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );

create policy resources_admin_write on storage.objects for all
  using (bucket_id = 'resources' and auth_has_role('wasa_admin'))
  with check (bucket_id = 'resources' and auth_has_role('wasa_admin'));

-- ---- 0010_seed_gentri_wasa.sql ----

insert into associations (id, name, province, municipality)
values ('00000000-0000-0000-0000-000000000001', 'GENTRI WASA', 'Cavite', 'General Trias')
on conflict (id) do nothing;

insert into barangays (association_id, name)
select '00000000-0000-0000-0000-000000000001', name
from (values
  ('Alingaro'),
  ('Arnaldo (Poblacion 7)'),
  ('Bacao I'),
  ('Bacao II'),
  ('Bagumbayan (Poblacion 5)'),
  ('Biclatan'),
  ('Buenavista I'),
  ('Buenavista II'),
  ('Buenavista III'),
  ('Corregidor (Poblacion 10)'),
  ('Dulong Bayan (Poblacion 3)'),
  ('Gov. Ferrer (Poblacion 1)'),
  ('Javalera'),
  ('Manggahan'),
  ('Navarro'),
  ('Ninety Sixth (Poblacion 8)'),
  ('Panungyanan'),
  ('Pasong Camachile I'),
  ('Pasong Camachile II'),
  ('Pasong Kawayan I'),
  ('Pasong Kawayan II'),
  ('Pinagtipunan'),
  ('Prinza (Poblacion 9)'),
  ('Sampalucan (Poblacion 2)'),
  ('San Francisco'),
  ('San Gabriel (Poblacion 4)'),
  ('San Juan I'),
  ('San Juan II'),
  ('Santa Clara'),
  ('Santiago'),
  ('Tapia'),
  ('Tejero'),
  ('Vibora (Poblacion 6)')
) as b(name)
on conflict (association_id, name) do nothing;
