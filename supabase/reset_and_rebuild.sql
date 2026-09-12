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
  operating_days smallint[],
  opens_at time,
  closes_at time,
  accreditation_override_by uuid references profiles(id),
  accreditation_override_at timestamptz,
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

  if exists (select 1 from memberships where profile_id = auth.uid()) then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
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
  if exists (select 1 from memberships where profile_id = auth.uid() and role = 'public_consumer') then
    return;
  end if;

  if exists (select 1 from memberships where profile_id = auth.uid()) then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
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
  'alkaline_water_test',
  'fire_safety_certificate',
  'nwrb_water_permit',
  'nwrb_certificate_of_public_convenience',
  'water_quality_test_report',
  'operator_training_certificate'
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
      (new.id, 'sanitary_permit', true),
      (new.id, 'fda_license', true),
      (new.id, 'fire_safety_certificate', true),
      (new.id, 'nwrb_water_permit', true),
      (new.id, 'nwrb_certificate_of_public_convenience', true),
      (new.id, 'water_quality_test_report', true),
      (new.id, 'operator_training_certificate', true)
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
  v_override_active boolean;
begin
  select (accreditation_override_by is not null) into v_override_active
    from water_stations where id = new.station_id;

  if v_override_active then
    -- A WASA admin has manually certified this station regardless of
    -- permit status -- don't let a later permit change silently undo it.
    return new;
  end if;

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

-- wasa_admin only: manually certify a station as accredited despite
-- missing/rejected required permits, or clear that override and let the
-- normal automatic computation (above) take over again.
create or replace function set_accreditation_override(p_station_id uuid, p_enable boolean) returns void as $$
declare
  v_all_ok boolean;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA admin may override a station''s accreditation.';
  end if;

  if p_enable then
    update water_stations
      set is_accredited = true,
          accreditation_status = 'accredited',
          accreditation_override_by = auth.uid(),
          accreditation_override_at = now(),
          updated_at = now()
      where id = p_station_id;
  else
    select not exists (
      select 1 from permits
      where station_id = p_station_id and is_required = true and status <> 'approved'
    ) into v_all_ok;

    update water_stations
      set accreditation_override_by = null,
          accreditation_override_at = null,
          is_accredited = v_all_ok,
          accreditation_status = case when v_all_ok then 'accredited' else 'under_review' end,
          updated_at = now()
      where id = p_station_id;
  end if;
end;
$$ language plpgsql security definer set search_path = public;

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
  v_current_station_id uuid;
begin
  select id, station_id into v_worker_id, v_current_station_id from workers where profile_id = auth.uid();

  if v_worker_id is not null then
    if v_current_station_id is not null then
      return v_worker_id;
    end if;

    -- Previously left/removed from a station -- re-link to the new one
    -- instead of silently returning a stale, still-unlinked id.
    select id, association_id into v_station_id, v_association_id
      from water_stations where invite_code ilike p_invite_code;
    if v_station_id is null then
      raise exception 'Invalid station invite code.';
    end if;

    update workers set station_id = v_station_id, updated_at = now() where id = v_worker_id;
    update memberships set station_id = v_station_id, association_id = v_association_id
      where profile_id = auth.uid() and role = 'driver';
    insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_station_id);
    return v_worker_id;
  end if;

  if exists (select 1 from memberships where profile_id = auth.uid()) then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
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

  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');

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

  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');

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

  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = p_worker_id and status in ('assigned', 'active');

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
  jug_type text,
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
  -- is_active is the WASA-admin-controlled enable/suspend flag;
  -- accepts_new_orders is the owner's own "open/closed right now" toggle
  -- (merchant_profile_screens.dart) -- deliberately separate columns so an
  -- owner flipping their own open/closed status can never override an
  -- admin suspension (see trg_prevent_owner_self_accreditation, which
  -- blocks owners from touching is_active at all).
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

create or replace function set_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_driver_worker_id uuid default null,
  p_guest_phone text default null,
  p_empty_jugs_returned int default null,
  p_payment_collected boolean default null
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

  -- Customer / guest: cancel their own order only, before it's out for delivery.
  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  -- Station owner / WASA admin: assign, cancel, unassign.
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

  -- Driver: start/complete their own assigned delivery only.
  select id into v_caller_worker_id from workers where profile_id = auth.uid();
  if v_caller_worker_id is not null and o.driver_worker_id = v_caller_worker_id then
    if o.status = 'assigned' and p_new_status = 'active' then
      update orders set status = 'active' where id = p_order_id;
      return;
    elsif o.status in ('assigned', 'active') and p_new_status = 'done' then
      update orders set status = 'done',
        empty_jugs_returned = coalesce(p_empty_jugs_returned, empty_jugs_returned),
        payment_collected = coalesce(p_payment_collected, payment_collected)
      where id = p_order_id;
      return;
    else
      raise exception 'Not a valid status change for a driver.';
    end if;
  end if;

  raise exception 'Not authorized to change this order.';
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
       or new.station_id is distinct from old.station_id
       or new.driver_worker_id is distinct from old.driver_worker_id then
      raise exception 'Drivers may not modify order financial, station, or assignment details.';
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

-- Reuses jug_type (above) for the station-facing "which containers do you
-- fill" question -- a customer-discovery detail, distinct from the
-- inter-station clearinghouse ledger below but sharing the same enum.
alter table water_stations add column offered_jug_types jug_type[] not null default '{}';
alter table water_stations add column offers_jug_exchange boolean not null default false;

-- Owner-controlled "open right now" toggle, deliberately separate from
-- is_active (the WASA-admin-only enable/suspend flag guarded by
-- trg_prevent_owner_self_accreditation below) -- an owner closing for the
-- day can never accidentally/intentionally undo an admin suspension.
alter table water_stations add column accepts_new_orders boolean not null default true;

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
  v_owed int;
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

  select coalesce(sum(quantity), 0) into v_owed
    from jug_ledger_entries
    where holder_station_id = s.holder_station_id
      and owner_station_id = s.owner_station_id
      and jug_type = s.jug_type;

  if s.quantity > v_owed then
    raise exception 'This settlement (% jugs) exceeds the current outstanding balance (% jugs).', s.quantity, v_owed;
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
  using (driver_worker_id = (select id from workers where profile_id = auth.uid()));
create policy orders_driver_update on orders for update
  using (driver_worker_id = (select id from workers where profile_id = auth.uid()));
create policy orders_customer_read on orders for select
  using (customer_profile_id = auth.uid());
-- No direct-insert policy for anon/authenticated -- all order creation goes
-- through insert_quick_order() (security definer, bypasses RLS as the
-- function owner), which enforces accepts-new-orders/is_active and
-- idempotency checks a raw client insert could otherwise skip entirely.
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

-- =====================================================================
-- PATCHES APPLIED AFTER 2026-09-03
--
-- This file was last regenerated on 2026-09-03. Everything below was
-- applied to the live database afterwards, and is appended verbatim in
-- the order it was applied (supabase_migrations.schema_migrations), so a
-- rebuild reproduces the live schema. Each patch is idempotent.
--
-- When adding a new patch, append it here as well -- mirroring only one
-- piece into the body above is how this file fell five patches behind,
-- and a partial mirror can reference columns a rebuild does not have.
-- =====================================================================


-- ---------------------------------------------------------------------
-- supabase/patch_jug_provenance.sql  (live migration 20260907154654)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Jug provenance tracking: closes the gap where jug_ledger_entries was
-- never actually populated by real deliveries -- only by a station
-- owner manually typing a net quantity with no link to what caused it.
-- A customer now declares which station's jug they're returning (if
-- exchanging), the driver confirms/corrects it at delivery, and
-- set_order_status automatically records the resulting inter-station
-- debt, linked to the order that caused it (jug_ledger_entries.related_order_id,
-- which existed but was never populated until now).
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

alter table orders add column if not exists jug_exchange_origin_station_id uuid references water_stations(id);

-- ---- insert_quick_order: customer declares jug origin at order time ----
-- Only stored when the ordering station actually offers jug exchange and
-- the declared origin isn't the ordering station itself (returning your
-- own station's jug needs no ledger entry) -- anything else is silently
-- ignored rather than rejected, since the driver gets a chance to
-- confirm/correct this at delivery anyway.

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
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
  v_accepts_new_orders boolean;
  v_offers_jug_exchange boolean;
  v_origin uuid;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select is_active, accepts_new_orders, offers_jug_exchange
    into v_is_active, v_accepts_new_orders, v_offers_jug_exchange
    from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active or not coalesce(v_accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;

  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(v_offers_jug_exchange, false)
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
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- set_order_status: driver confirms/corrects jug origin, and the ----
-- ---- resulting jug_ledger_entries row is written automatically       ----
-- Re-declared (not just CREATE OR REPLACE) with two new trailing params
-- -- unlike insert_quick_order's history, existing callers of this
-- function pass different SUBSETS of its named parameters (e.g.
-- unassignOrder passes only p_order_id/p_new_status), so simply adding
-- an overload would make every such call ambiguous between the old and
-- new signatures ("could not choose the best candidate function").
-- Dropping the old one first keeps there being exactly one candidate.

drop function if exists set_order_status(uuid, order_status, uuid, text, int, boolean);

create function set_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_driver_worker_id uuid default null,
  p_guest_phone text default null,
  p_empty_jugs_returned int default null,
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

  -- Customer / guest: cancel their own order only, before it's out for delivery.
  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  -- Station owner / WASA admin: assign, cancel, unassign.
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

  -- Driver: start/complete their own assigned delivery only.
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

      -- Automatic jug-provenance capture: closes the gap where this table
      -- was only ever populated by a manual, order-disconnected guess.
      -- jug_type is guarded against anything other than the two known
      -- container shapes since orders.jug_type is free text (mirrors
      -- water_type's convention) while jug_ledger_entries.jug_type is the
      -- enum -- an unexpected value here should never block completing a
      -- delivery.
      if o.jug_exchange_origin_station_id is not null
         and o.jug_exchange_origin_station_id <> o.station_id
         and o.jug_type in ('slim_5gal', 'round_5gal')
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
-- supabase/patch_website_content_cms.sql  (live migration 20260907162616)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Website content management: admin-editable content for the six static
-- website pages (About, FAQ, Contact, For Station Owners, How
-- Accreditation Works, Jug Clearinghouse Explainer), which previously had
-- no admin editor at all -- their copy was hardcoded directly in the
-- Dart widget trees. Follows the exact pattern already proven by
-- `bulletins` (public-read/admin-write RLS + a service + an admin
-- editor screen).
--
-- Also fixes a real, already-drifting bug found while researching this:
-- permit type display labels/condition notes were hardcoded
-- independently in permit_vault_screen.dart, permit_review_screen.dart,
-- and how_accreditation_works_screen.dart -- three separate copies kept
-- in sync only by hand (a recently-added permit type required editing
-- all three). `permit_type_labels` collapses these into one shared,
-- admin-editable source that both the app and the website read.
--
-- Every table is seeded verbatim from the current hardcoded copy, so
-- nothing visibly changes on first deploy -- admin can edit from there.
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

create table if not exists web_page_sections (
  id uuid primary key default gen_random_uuid(),
  page_key text not null,
  section_key text not null,
  title text,
  body text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now(),
  unique (page_key, section_key)
);

create table if not exists web_content_items (
  id uuid primary key default gen_random_uuid(),
  page_key text not null,
  item_key text not null,
  icon text,
  title text not null,
  body text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

create index if not exists web_content_items_page_item_idx on web_content_items (page_key, item_key, sort_order);

create table if not exists web_faq_entries (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  answer text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

-- One row per permit_type enum value (currently 10). Update-only for
-- admin -- the row set is fixed by the enum, so there's no insert/delete
-- policy, only select/update.
create table if not exists permit_type_labels (
  permit_type permit_type primary key,
  label text not null,
  condition_note text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

alter table web_page_sections enable row level security;
alter table web_content_items enable row level security;
alter table web_faq_entries enable row level security;
alter table permit_type_labels enable row level security;

create policy web_page_sections_public_read on web_page_sections for select using (true);
create policy web_page_sections_admin_insert on web_page_sections for insert with check (auth_has_role('wasa_admin'));
create policy web_page_sections_admin_update on web_page_sections for update using (auth_has_role('wasa_admin'));
create policy web_page_sections_admin_delete on web_page_sections for delete using (auth_has_role('wasa_admin'));

create policy web_content_items_public_read on web_content_items for select using (true);
create policy web_content_items_admin_insert on web_content_items for insert with check (auth_has_role('wasa_admin'));
create policy web_content_items_admin_update on web_content_items for update using (auth_has_role('wasa_admin'));
create policy web_content_items_admin_delete on web_content_items for delete using (auth_has_role('wasa_admin'));

create policy web_faq_entries_public_read on web_faq_entries for select using (true);
create policy web_faq_entries_admin_insert on web_faq_entries for insert with check (auth_has_role('wasa_admin'));
create policy web_faq_entries_admin_update on web_faq_entries for update using (auth_has_role('wasa_admin'));
create policy web_faq_entries_admin_delete on web_faq_entries for delete using (auth_has_role('wasa_admin'));

create policy permit_type_labels_public_read on permit_type_labels for select using (true);
create policy permit_type_labels_admin_update on permit_type_labels for update using (auth_has_role('wasa_admin'));

-- ---- Seed: About -- "What WASA Does" bullets ----
insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('about', 'what_wasa_does', '', 'Reviews and accredits refilling stations before they can display the WASA verification seal.', 0),
  ('about', 'what_wasa_does', '', 'Maintains a shared worker security registry, so a driver flagged for an incident at one station can''t simply move to another unnoticed.', 1),
  ('about', 'what_wasa_does', '', 'Sets and enforces minimum floor prices to prevent predatory undercutting between member stations.', 2),
  ('about', 'what_wasa_does', '', 'Coordinates the inter-station jug clearinghouse, so reusable 5-gallon containers get settled fairly between stations.', 3)
on conflict do nothing;

-- ---- Seed: FAQ ----
insert into web_faq_entries (question, answer, sort_order) values
  ('Who can order water through GENTRI WASA?', 'Anyone can browse the station directory and community bulletin without an account. Placing an order requires a free customer account, so deliveries are tied to a real, trackable identity rather than anonymous device state.', 0),
  ('How do I know a station is legitimate?', 'Look for the green "WASA Verified" seal on the station directory and map. It only appears once every required permit has been reviewed and approved by a WASA admin -- a station cannot grant itself this seal.', 1),
  ('What permits does a station need to get accredited?', 'A Mayor''s Business Permit, a Sanitary Permit, and an FDA License to Operate are required for every station. Stations offering alkaline water also need an Alkaline Machine Technical Certification and an Alkaline Water Quality Test Report.', 2),
  ('How long does accreditation review take?', 'There''s no fixed timeline -- a WASA admin reviews each uploaded document individually and either approves it or rejects it with a stated reason, so an owner always knows exactly what to fix and can re-upload immediately.', 3),
  ('Can I schedule a delivery instead of ordering ASAP?', 'Yes -- the order form has an ASAP/Scheduled toggle. Choosing Scheduled lets you pick a future date and time for delivery instead of requesting the soonest available driver.', 4),
  ('How do I pay?', 'Cash on delivery. The total (jugs x price, plus delivery fee) is shown before you confirm the order and again when the driver arrives.', 5),
  ('What is the floor price, and why does it exist?', 'WASA sets a minimum price per water type across all member stations, so no station can undercut competitors to the point of predatory pricing. Every station''s price must stay at or above this floor.', 6),
  ('What happens if I have a problem with a driver or station?', 'Station owners can file a security incident against a worker through the shared clearance registry, which follows that worker even if they move to another member station. Residents can reach the association directly through the Contact page.', 7)
on conflict do nothing;

-- ---- Seed: Contact ----
insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('contact', 'address', '[Placeholder] Association Office Address, General Trias, Cavite', 0),
  ('contact', 'hours', '[Placeholder] Office Hours: Monday-Friday, 8:00 AM - 5:00 PM', 1),
  ('contact', 'email', 'contact@gentriwasa.example', 2)
on conflict do nothing;

-- ---- Seed: For Station Owners ----
insert into web_content_items (page_key, item_key, icon, title, body, sort_order) values
  ('for_station_owners', 'benefits', 'verified', 'Official Recognition', 'Accredited stations get the WASA verification seal on the public directory and map.', 0),
  ('for_station_owners', 'benefits', 'security', 'Worker Accountability', 'Screen prospective drivers/helpers against the shared cross-station clearance registry before hiring.', 1),
  ('for_station_owners', 'benefits', 'price_change', 'Fair Pricing Protection', 'Association-wide floor prices protect member stations from predatory undercutting.', 2),
  ('for_station_owners', 'benefits', 'swap_horiz', 'Jug Clearinghouse', 'Settle Slim/Round 5-gallon jug balances with other stations through one shared ledger.', 3)
on conflict do nothing;

insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('for_station_owners', 'requirements_summary', 'Business Permit, Sanitary Permit, FDA License to Operate, a Fire Safety Inspection Certificate, a Water Quality Test Report, and an Operator Training Certificate at minimum -- plus additional certifications if you offer alkaline water or source your own well water.', 0)
on conflict do nothing;

-- ---- Seed: How Accreditation Works -- process steps ----
insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('how_accreditation_works', 'steps', 'Register the station', 'The owner creates an account and registers their station with basic details (name, address, offered water types).', 0),
  ('how_accreditation_works', 'steps', 'Upload required documents', 'Every station uploads its Business Permit, Sanitary Permit, FDA License, Fire Safety Inspection Certificate, Water Quality Test Report, and Operator Training Certificate. Stations offering alkaline water also upload two additional certifications, and WASA may require the NWRB Water Permit/Certificate of Public Convenience for stations sourcing their own well water.', 1),
  ('how_accreditation_works', 'steps', 'WASA reviews each document', 'A WASA admin reviews every uploaded document individually -- approving, or rejecting with a stated reason so the owner knows exactly what to fix.', 2),
  ('how_accreditation_works', 'steps', 'Accreditation is automatic once complete', 'The moment every required document is approved, the station is automatically marked accredited -- no separate manual step, and no way for a station to grant itself accreditation.', 3),
  ('how_accreditation_works', 'steps', 'The colorum-verification seal appears', 'Accredited, WASA-verified stations get the verification seal on the public station directory, so residents can tell a legitimate operator from an unlicensed one at a glance.', 4)
on conflict do nothing;

-- ---- Seed: Jug Clearinghouse Explainer ----
-- Step 1's copy is corrected here (not just copied verbatim) -- it used
-- to describe the old fully-manual recording flow; patch_jug_provenance.sql
-- made this automatic at delivery completion, so the explainer should
-- say that, not the outdated mechanism.
insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('jug_clearinghouse', 'intro', 'Reusable Slim and Round 5-gallon jugs regularly end up at a different station than the one that owns them -- a driver delivers water in one station''s jug, and picks up an empty jug bearing a competitor''s brand. Without a shared system, that jug is effectively lost to its owner. The clearinghouse makes those swaps fair and auditable across the whole association.', 0)
on conflict do nothing;

insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('jug_clearinghouse', 'steps', 'A jug crosses station lines', 'When a customer exchanges an empty jug at a different station than the one that owns it, the app automatically records who now holds the jug and who it belongs to as soon as the delivery is completed.', 0),
  ('jug_clearinghouse', 'steps', 'The ledger tracks who holds what', 'Every cross-station transfer is logged as a ledger entry -- which station now holds the jug, and which station originally owns it.', 1),
  ('jug_clearinghouse', 'steps', 'Balances net out automatically', 'Instead of settling jug-by-jug, the system nets all transfers between two stations into a single running balance per jug type.', 2),
  ('jug_clearinghouse', 'steps', 'Stations propose and confirm settlement', 'A holder station proposes a settlement to clear its balance; the owner station confirms or rejects it. Confirming atomically posts the offsetting ledger entry, so the balance can''t drift or be double-counted.', 3)
on conflict do nothing;

-- ---- Seed: permit type labels (all 10 known values) ----
insert into permit_type_labels (permit_type, label, condition_note, sort_order) values
  ('business_permit', 'Mayor''s Business Permit', 'Required for every station.', 0),
  ('sanitary_permit', 'Sanitary Permit', 'Required for every station.', 1),
  ('fda_license', 'FDA License to Operate', 'Required for every station.', 2),
  ('fire_safety_certificate', 'Fire Safety Inspection Certificate (BFP)', 'Required for every station.', 3),
  ('water_quality_test_report', 'Water Quality Test Report (DOH)', 'Required for every station.', 4),
  ('operator_training_certificate', 'Operator Training Certificate (CCWRSPO)', 'Required for every station.', 5),
  ('alkaline_tech_cert', 'Alkaline Machine Technical Certification', 'Only required if the station offers alkaline water.', 6),
  ('alkaline_water_test', 'Alkaline Water Quality Test Report', 'Only required if the station offers alkaline water.', 7),
  ('nwrb_water_permit', 'NWRB Water Permit', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 8),
  ('nwrb_certificate_of_public_convenience', 'NWRB Certificate of Public Convenience', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 9)
on conflict (permit_type) do nothing;


-- ---------------------------------------------------------------------
-- supabase/patch_accredited_at.sql  (live migration 20260908111123)
-- ---------------------------------------------------------------------
-- Records WHEN a station became accredited, so the admin dashboard can chart
-- accreditations over time.
--
-- Why this is needed: water_stations has created_at (registered),
-- updated_at (last edited, for any reason) and accreditation_override_at
-- (manual certification only). None of them answers "when did this station
-- become accredited". Charting updated_at would silently mislabel "someone
-- edited the phone number" as "accredited this month".
--
-- Why a trigger rather than editing the functions that grant accreditation:
-- is_accredited is written from two places -- recompute_accreditation()
-- (patch_admin_accreditation_override.sql) when a permit changes, and
-- set_accreditation_override() when an admin manually certifies. A BEFORE
-- UPDATE trigger on the transition catches both, plus any future path,
-- without touching either function's logic.
--
-- Historical rows stay null on purpose: there is no honest way to backfill a
-- date that was never recorded, so the dashboard labels its earliest bucket
-- rather than inventing history. Idempotent -- safe to run more than once.

alter table water_stations add column if not exists accredited_at timestamptz;

comment on column water_stations.accredited_at is
  'When is_accredited last became true. Null for stations accredited before this column existed, and cleared if accreditation is lost.';

create or replace function stamp_accredited_at() returns trigger as $$
begin
  if new.is_accredited and not coalesce(old.is_accredited, false) then
    -- false -> true: this is the moment of accreditation.
    new.accredited_at := now();
  elsif not new.is_accredited then
    -- Lost (or never had) accreditation. Clearing means a station that is
    -- re-accredited later gets the new date rather than a stale first one,
    -- which is what "accredited this quarter" should count.
    new.accredited_at := null;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at on water_stations;
create trigger trg_stamp_accredited_at
  before update on water_stations
  for each row
  when (old.is_accredited is distinct from new.is_accredited)
  execute function stamp_accredited_at();

-- A station inserted already accredited would otherwise never fire the
-- update trigger.
create or replace function stamp_accredited_at_insert() returns trigger as $$
begin
  if new.is_accredited then
    new.accredited_at := coalesce(new.accredited_at, now());
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at_insert on water_stations;
create trigger trg_stamp_accredited_at_insert
  before insert on water_stations
  for each row
  execute function stamp_accredited_at_insert();

create index if not exists water_stations_accredited_at_idx
  on water_stations (accredited_at)
  where accredited_at is not null;


-- ---------------------------------------------------------------------
-- supabase/patch_admin_activity_view.sql  (live migration 20260908114008 + 20260908114423 (actor_name))
-- ---------------------------------------------------------------------
-- Read-only "who did what" feed for the WASA admin portal.
--
-- Every admin mutation in this schema already stamps an actor and a
-- timestamp -- permits.reviewed_by/at, worker_incidents.resolved_by/at,
-- worker_credentials.reviewed_by/at, water_stations.accreditation_override_
-- by/at, and updated_by/at on all four CMS tables. Until now exactly one of
-- those was ever read back (permit_review_screen.dart renders "manually
-- certified by X"), so an admin could not answer "who suspended this
-- account?" or "what did I approve last week?"
--
-- This is a view, not a new audit table: the data is already being written,
-- so logging it a second time would add a write path that could disagree
-- with the records it is supposed to describe. The trade-off is that it only
-- shows the LATEST action per row -- re-reviewing a permit overwrites
-- reviewed_at, so this is an activity feed, not a full history. A real
-- append-only audit log would be a separate change.
--
-- security_invoker = on so the querying user's own RLS applies: admins
-- already have read access to every underlying table and nobody else does,
-- so this view cannot become a way around those policies.

create or replace view admin_activity
with (security_invoker = on) as
select a.actor_id, a.occurred_at, a.category, a.action, a.subject,
       coalesce(pr.full_name, 'Unknown') as actor_name
from (
  select
    p.reviewed_by                              as actor_id,
    p.reviewed_at                              as occurred_at,
    'Permit'                                   as category,
    case p.status::text
      when 'approved' then 'Approved permit'
      when 'rejected' then 'Rejected permit'
      else 'Reviewed permit'
    end                                        as action,
    coalesce(ws.station_name, 'Unknown station') || ' - ' || p.permit_type::text as subject
  from permits p
  left join water_stations ws on ws.id = p.station_id
  where p.reviewed_by is not null and p.reviewed_at is not null

  union all

  select
    wi.resolved_by,
    wi.resolved_at,
    'Worker incident',
    case wi.status::text
      when 'confirmed_flag' then 'Confirmed flag on'
      when 'dismissed' then 'Dismissed incident for'
      else 'Resolved incident for'
    end,
    coalesce(w.full_name, 'Unknown worker')
  from worker_incidents wi
  left join workers w on w.id = wi.worker_id
  where wi.resolved_by is not null and wi.resolved_at is not null

  union all

  select
    wc.reviewed_by,
    wc.reviewed_at,
    'Worker credential',
    case wc.status::text
      when 'approved' then 'Approved credential for'
      when 'rejected' then 'Rejected credential for'
      else 'Reviewed credential for'
    end,
    coalesce(w.full_name, 'Unknown worker') || ' (' || wc.credential_type::text || ')'
  from worker_credentials wc
  left join workers w on w.id = wc.worker_id
  where wc.reviewed_by is not null and wc.reviewed_at is not null

  union all

  select
    ws.accreditation_override_by,
    ws.accreditation_override_at,
    'Accreditation',
    'Manually certified',
    ws.station_name
  from water_stations ws
  where ws.accreditation_override_by is not null and ws.accreditation_override_at is not null

  union all

  select s.updated_by, s.updated_at, 'Website content', 'Edited section', s.page_key || ' / ' || s.section_key
  from web_page_sections s
  where s.updated_by is not null

  union all

  select i.updated_by, i.updated_at, 'Website content', 'Edited item', i.page_key || ' / ' || i.item_key
  from web_content_items i
  where i.updated_by is not null

  union all

  select f.updated_by, f.updated_at, 'Website content', 'Edited FAQ', f.question
  from web_faq_entries f
  where f.updated_by is not null

  union all

  select l.updated_by, l.updated_at, 'Website content', 'Edited permit label', l.permit_type::text
  from permit_type_labels l
  where l.updated_by is not null
) a
left join profiles pr on pr.id = a.actor_id;

comment on view admin_activity is
  'Latest recorded admin action per row, unioned from the actor columns the app already writes. Activity feed, not an append-only audit log.';


-- ---------------------------------------------------------------------
-- supabase/patch_server_side_pricing.sql  (live migration 20260910204546)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- supabase/patch_permit_sync_fix.sql  (live migration 20260910225037)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a station owner with approved alkaline permits could not save their
-- station profile at all -- not even a name change.
--
-- Two triggers combined:
--   * trg_sync_required_permits fires AFTER UPDATE OF offered_water_types,
--     i.e. whenever that column is in the SET list -- and the profile screen
--     always sends it. It then re-upserted the alkaline permits with
--     DO UPDATE SET is_required = true even when they already were.
--   * That no-op UPDATE of an approved permit tripped
--     prevent_owner_self_permit_approval, which raised whenever a non-admin
--     updated a permit whose new.status = 'approved' -- whether or not
--     anything was being approved.
--
-- Found when the product-catalog migration (which updates stations' water
-- types) failed on Buenavista, whose alkaline permits are approved.
--
-- 1. An approval is a status CHANGE to approved, not "the row is approved".
-- 2. The permit sync does nothing when the water types didn't change, and
--    never rewrites a permit whose is_required already has the target value.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if (new.status = 'approved' and new.status is distinct from old.status)
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function sync_required_permits() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    if new.offered_water_types is not distinct from old.offered_water_types then
      return new;
    end if;
  end if;

  insert into permits (station_id, permit_type, is_required)
    values
      (new.id, 'business_permit', true),
      (new.id, 'sanitary_permit', true),
      (new.id, 'fda_license', true),
      (new.id, 'fire_safety_certificate', true),
      (new.id, 'nwrb_water_permit', true),
      (new.id, 'nwrb_certificate_of_public_convenience', true),
      (new.id, 'water_quality_test_report', true),
      (new.id, 'operator_training_certificate', true)
    on conflict (station_id, permit_type) do nothing;

  if 'alkaline' = any(new.offered_water_types) then
    insert into permits (station_id, permit_type, is_required)
      values
        (new.id, 'alkaline_tech_cert', true),
        (new.id, 'alkaline_water_test', true)
      on conflict (station_id, permit_type) do update set is_required = true
        where permits.is_required is distinct from true;
  else
    update permits set is_required = false
      where station_id = new.id
        and permit_type in ('alkaline_tech_cert', 'alkaline_water_test')
        and is_required;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- supabase/patch_product_catalog.sql  (live migration 20260910225241)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- supabase/patch_account_lifecycle.sql  (live migration 20260911151726)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_account_lifecycle.sql
--
-- Account deletion (Google Play requires an in-app way to delete an
-- account) and comment author names. Deletion itself runs in the
-- delete-account Edge Function, which uses the two service-role-only
-- functions defined here.
--
-- Decisions (association): a deleted customer's orders are anonymized, not
-- deleted; station owners, drivers and admins request deletion and WASA
-- admin completes it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. "Who did it" references to profiles no longer block deleting a
--    profile. They become NULL and the record they describe stays: the jug
--    ledger, settlements, floor prices, posts, events, resources, incident
--    reports, website edits, and a closed station's order history.
--    (memberships, reviews, comments and reactions already cascade.)
--    Every insert path still requires these to be the signed-in user (RLS),
--    so allowing NULL doesn't let anyone post anonymously.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values
    ('water_stations', 'owner_profile_id'),
    ('water_stations', 'accreditation_override_by'),
    ('workers', 'profile_id'),
    ('worker_incidents', 'reported_by_profile_id'),
    ('orders', 'customer_profile_id'),
    ('jug_ledger_entries', 'recorded_by'),
    ('jug_settlements', 'proposed_by'),
    ('jug_settlements', 'confirmed_by'),
    ('floor_prices', 'set_by'),
    ('bulletins', 'posted_by'),
    ('worker_station_history', 'ended_by_profile_id'),
    ('resources', 'uploaded_by'),
    ('events', 'created_by'),
    ('web_page_sections', 'updated_by'),
    ('web_content_items', 'updated_by'),
    ('web_faq_entries', 'updated_by'),
    ('permit_type_labels', 'updated_by')
  ) as v(tbl, col)
  loop
    execute format('alter table public.%I alter column %I drop not null', r.tbl, r.col);
    execute format('alter table public.%I drop constraint if exists %I', r.tbl, r.tbl || '_' || r.col || '_fkey');
    execute format(
      'alter table public.%I add constraint %I foreign key (%I) references public.profiles(id) on delete set null',
      r.tbl, r.tbl || '_' || r.col || '_fkey', r.col);
  end loop;
end $$;

-- posted_by can now be NULL, and "NULL <> auth.uid()" is NULL, not true --
-- so the old check let a NULL through. RLS already required
-- posted_by = auth.uid(); this makes the trigger agree.
create or replace function validate_bulletin_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.posted_by is distinct from auth.uid() then
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
$$;

-- ---------------------------------------------------------------------
-- 2. Comment author names, stored on the comment. profiles is readable
--    only by its owner and admin, so joining it showed every other
--    commenter as "Resident". Bulletins already store author_name the
--    same way.
-- ---------------------------------------------------------------------
alter table bulletin_comments add column if not exists author_name text;

update bulletin_comments c
   set author_name = coalesce(nullif(trim(p.full_name), ''), 'Resident')
  from profiles p
 where p.id = c.profile_id and c.author_name is null;

update bulletin_comments set author_name = 'Resident' where author_name is null;

create or replace function set_comment_author_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Always from the profile, never from the client.
  select coalesce(nullif(trim(full_name), ''), 'Resident') into new.author_name
    from profiles where id = new.profile_id;
  new.author_name := coalesce(new.author_name, 'Resident');
  return new;
end;
$$;

drop trigger if exists trg_set_comment_author_name on bulletin_comments;
create trigger trg_set_comment_author_name
  before insert on bulletin_comments
  for each row execute function set_comment_author_name();

-- ---------------------------------------------------------------------
-- 3. Deletion requests from station owners, drivers and admins.
-- ---------------------------------------------------------------------
create table if not exists account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  reason text check (reason is null or char_length(reason) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'cancelled')),
  requested_at timestamptz not null default now()
);

create unique index if not exists account_deletion_requests_one_pending
  on account_deletion_requests (profile_id) where status = 'pending';

alter table account_deletion_requests enable row level security;
revoke all on account_deletion_requests from anon;

drop policy if exists deletion_requests_self_read on account_deletion_requests;
create policy deletion_requests_self_read on account_deletion_requests
  for select using (profile_id = auth.uid());

drop policy if exists deletion_requests_self_insert on account_deletion_requests;
create policy deletion_requests_self_insert on account_deletion_requests
  for insert with check (profile_id = auth.uid() and status = 'pending');

drop policy if exists deletion_requests_self_withdraw on account_deletion_requests;
create policy deletion_requests_self_withdraw on account_deletion_requests
  for update using (profile_id = auth.uid())
  with check (profile_id = auth.uid() and status = 'cancelled');

drop policy if exists deletion_requests_admin_all on account_deletion_requests;
create policy deletion_requests_admin_all on account_deletion_requests
  for all using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- 4. Anonymize what outlives the account. Orders keep their items and
--    amounts for the station's records; the name, phones and exact
--    address go (the location is snapped to a ~1 km grid). Posts read
--    "Former member" and lose their image (the file is removed by the
--    Edge Function).
-- ---------------------------------------------------------------------
create or replace function anonymize_account(p_profile uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- guest_name gets a neutral label rather than NULL: the customer_or_guest
  -- check requires an order to have a customer or a guest name.
  update orders
     set customer_profile_id = null,
         guest_name = 'Former customer',
         guest_phone = null,
         customer_phone = null,
         delivery_location = st_setsrid(
           st_makepoint(
             round(st_x(delivery_location::geometry)::numeric, 2)::float8,
             round(st_y(delivery_location::geometry)::numeric, 2)::float8),
           4326)::geography
   where customer_profile_id = p_profile;

  update bulletins
     set author_name = 'Former member',
         author_station_name = null,
         image_url = null
   where posted_by = p_profile;
end;
$$;

revoke all on function anonymize_account(uuid) from public, anon, authenticated;
grant execute on function anonymize_account(uuid) to service_role;

-- ---------------------------------------------------------------------
-- 5. What stops an account from being deleted right now, each worded as
--    the step that clears it. Empty means it can go.
-- ---------------------------------------------------------------------
create or replace function account_deletion_blockers(p_profile uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_blockers text[] := array[]::text[];
  v_count int;
  v_station record;
begin
  select count(*) into v_count
    from orders
   where customer_profile_id = p_profile and status in ('pending', 'assigned', 'active');
  if v_count > 0 then
    v_blockers := array_append(v_blockers,
      format('%s order(s) still in progress. Wait for delivery or cancel them first.', v_count));
  end if;

  for v_station in
    select station_name from water_stations where owner_profile_id = p_profile and is_active
  loop
    v_blockers := array_append(v_blockers,
      format('Still the owner of %s, which is open. Close the station first.', v_station.station_name));
  end loop;

  select count(*) into v_count
    from orders o join workers w on w.id = o.driver_worker_id
   where w.profile_id = p_profile and o.status in ('assigned', 'active');
  if v_count > 0 then
    v_blockers := array_append(v_blockers,
      format('%s delivery(ies) assigned to this driver. Reassign or finish them first.', v_count));
  end if;

  if exists (select 1 from memberships where profile_id = p_profile and role = 'wasa_admin' and status = 'active')
     and (select count(*) from memberships where role = 'wasa_admin' and status = 'active') <= 1 then
    v_blockers := array_append(v_blockers, 'This is the only active WASA admin account. Add another admin first.');
  end if;

  return v_blockers;
end;
$$;

revoke all on function account_deletion_blockers(uuid) from public, anon, authenticated;
grant execute on function account_deletion_blockers(uuid) to service_role;

-- ---------------------------------------------------------------------
-- supabase/patch_notifications.sql  (live migration 20260911235109)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_notifications.sql
--
-- Nothing in the product ever told anyone anything: a customer didn't
-- learn their order was accepted, an owner didn't learn an order arrived,
-- a driver didn't learn they were assigned. This adds an in-app inbox fed
-- by database triggers, so the message is written once, server-side, for
-- every client.
--
-- It also publishes `orders` for Realtime. The owner's Orders screen has
-- always subscribed to live updates (orders_screen.dart), but no table was
-- published, so that "live" list only ever refreshed when reopened.
--
-- Phone push (FCM) is deliberately not here -- it needs the association's
-- final app ID. It will read the same rows.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The inbox. Written only by the triggers below (SECURITY DEFINER):
--    there is no insert policy, so no client can post a notification.
-- ---------------------------------------------------------------------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  category text not null check (category in ('order', 'permit', 'accreditation', 'account')),
  title text not null,
  body text,
  order_id uuid references orders(id) on delete set null,
  station_id uuid references water_stations(id) on delete set null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_profile_created_idx
  on notifications (profile_id, created_at desc);

alter table notifications enable row level security;
revoke all on notifications from anon;

drop policy if exists notifications_self_read on notifications;
create policy notifications_self_read on notifications
  for select using (profile_id = auth.uid());

drop policy if exists notifications_self_mark_read on notifications;
create policy notifications_self_mark_read on notifications
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

drop policy if exists notifications_self_delete on notifications;
create policy notifications_self_delete on notifications
  for delete using (profile_id = auth.uid());

-- ---------------------------------------------------------------------
-- 2. One order line, worded the same way the app words it
--    (describeOrderLine, lib/models/order.dart).
-- ---------------------------------------------------------------------
create or replace function order_line_text(
  p_quantity integer,
  p_water_type text,
  p_container_code text,
  p_product_kind text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_label text;
  v_water text := initcap(coalesce(p_water_type, ''));
begin
  select label into v_label from container_types where code = p_container_code;
  if v_label is null then
    return p_quantity || ' × ' || v_water;
  end if;
  return p_quantity || ' × ' || v_label
    || case p_product_kind when 'refill' then ' refill' when 'new_container' then ' (new)' else '' end
    || case when v_water = '' then '' else ' · ' || v_water end;
end;
$$;

create or replace function peso_text(p_amount numeric)
returns text language sql immutable as $$
  select '₱' || trim(to_char(coalesce(p_amount, 0), 'FM999999990.00'));
$$;

-- ---------------------------------------------------------------------
-- 3. Order events -> the people they concern.
-- ---------------------------------------------------------------------
create or replace function notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_station_name text;
  v_driver_profile uuid;
  v_line text;
begin
  select owner_profile_id, station_name into v_owner, v_station_name
    from water_stations where id = new.station_id;
  v_line := order_line_text(new.jugs_ordered, new.water_type, new.jug_type, new.product_kind);

  -- A new order: the station owner needs to see it.
  if tg_op = 'INSERT' then
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id);
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if new.customer_profile_id is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (
        new.customer_profile_id, 'order',
        case new.status
          when 'assigned' then 'A driver is on the way'
          when 'active' then 'Your order is out for delivery'
          when 'done' then 'Order delivered'
          when 'cancelled' then 'Order cancelled'
          else 'Order updated'
        end,
        coalesce(v_station_name, 'Your station') || ' · ' || v_line,
        new.id, new.station_id);
    end if;

    if new.status = 'cancelled' and v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'Order cancelled', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id);
    end if;
  end if;

  -- Assigned to a driver (status and driver can change in the same update).
  if new.driver_worker_id is not null and new.driver_worker_id is distinct from old.driver_worker_id then
    select profile_id into v_driver_profile from workers where id = new.driver_worker_id;
    if v_driver_profile is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_driver_profile, 'order', 'Delivery assigned', v_line, new.id, new.station_id);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_order_event on orders;
create trigger trg_notify_order_event
  after insert or update on orders
  for each row execute function notify_order_event();

-- ---------------------------------------------------------------------
-- 4. Permit decisions and accreditation changes -> the station owner.
-- ---------------------------------------------------------------------
create or replace function notify_permit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_station text;
  v_label text;
begin
  if new.status is not distinct from old.status or new.status not in ('approved', 'rejected') then
    return new;
  end if;

  select owner_profile_id, station_name into v_owner, v_station
    from water_stations where id = new.station_id;
  if v_owner is null then
    return new;
  end if;

  select label into v_label from permit_type_labels where permit_type = new.permit_type;
  v_label := coalesce(v_label, initcap(replace(new.permit_type::text, '_', ' ')));

  insert into notifications (profile_id, category, title, body, station_id)
  values (
    v_owner, 'permit',
    case new.status when 'approved' then v_label || ' approved' else v_label || ' was rejected' end,
    case
      when new.status = 'rejected' and new.rejection_reason is not null then new.rejection_reason
      else coalesce(v_station, '')
    end,
    new.station_id);
  return new;
end;
$$;

drop trigger if exists trg_notify_permit_review on permits;
create trigger trg_notify_permit_review
  after update on permits
  for each row execute function notify_permit_review();

create or replace function notify_accreditation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.accreditation_status::text is not distinct from old.accreditation_status::text
     or new.owner_profile_id is null then
    return new;
  end if;

  insert into notifications (profile_id, category, title, body, station_id)
  values (
    new.owner_profile_id, 'accreditation',
    case new.accreditation_status::text
      when 'accredited' then 'Your station is accredited'
      else 'Accreditation status: ' || replace(new.accreditation_status::text, '_', ' ')
    end,
    new.station_name, new.id);
  return new;
end;
$$;

drop trigger if exists trg_notify_accreditation_change on water_stations;
create trigger trg_notify_accreditation_change
  after update on water_stations
  for each row execute function notify_accreditation_change();

-- ---------------------------------------------------------------------
-- 5. Realtime. Row-level security still applies to what each client
--    receives, so everyone only ever sees their own rows.
-- ---------------------------------------------------------------------
alter table notifications replica identity full;
alter table orders replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table notifications;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'orders') then
    alter publication supabase_realtime add table orders;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- supabase/patch_customer_addresses.sql  (live migration 20260912012730)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_customer_addresses.sql
--
-- Customers had to drop a pin on the map for every single order, even
-- when ordering to the same house every week. This stores the places a
-- customer orders to, labelled, with one default that the order form
-- pre-selects.
--
-- Only the customer can see or change their own; the address only reaches
-- a station through the order they place (orders.delivery_location),
-- exactly as before.
-- =====================================================================

create table if not exists customer_addresses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 40),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  notes text check (notes is null or char_length(notes) <= 200),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists customer_addresses_profile_idx on customer_addresses (profile_id, created_at);

-- At most one default each, enforced rather than hoped for.
create unique index if not exists customer_addresses_one_default
  on customer_addresses (profile_id) where is_default;

alter table customer_addresses enable row level security;
revoke all on customer_addresses from anon;

drop policy if exists customer_addresses_self_all on customer_addresses;
create policy customer_addresses_self_all on customer_addresses
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Marking one default clears the previous one, so saving never fails on
-- the unique index above.
create or replace function enforce_single_default_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_default then
    update customer_addresses
       set is_default = false
     where profile_id = new.profile_id and id <> new.id and is_default;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_single_default_address on customer_addresses;
create trigger trg_enforce_single_default_address
  before insert or update on customer_addresses
  for each row execute function enforce_single_default_address();
