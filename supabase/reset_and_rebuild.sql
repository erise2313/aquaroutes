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
-- Tables added by the patches further down this file. They are NOT
-- removed by dropping their parents: `drop table bulletins cascade` drops
-- the foreign KEY in bulletin_comments, not the TABLE, so it survives and
-- the later `create table bulletin_comments` collides with it. Four of
-- these are created without `if not exists` and fail outright on a re-run
-- (bulletin_comments, reviews, resources, events); the rest would silently
-- keep stale rows from the previous run. Dropped children-first.
drop table if exists station_reports cascade;
drop table if exists station_cost_profiles cascade;
drop table if exists event_rsvps cascade;
drop table if exists notification_preferences cascade;
drop table if exists trash cascade;
drop table if exists storage_cleanup cascade;
drop table if exists compliance_cases cascade;
drop table if exists notice_receipts cascade;
drop table if exists notices cascade;
drop table if exists compliance_reminders cascade;
drop table if exists association_settings cascade;
drop table if exists web_content_revisions cascade;
drop table if exists audit_log cascade;
drop table if exists bulletin_reports cascade;
drop table if exists favorite_stations cascade;
drop table if exists customer_addresses cascade;
drop table if exists notifications cascade;
drop table if exists account_deletion_requests cascade;
drop table if exists station_products cascade;
drop table if exists container_types cascade;
drop table if exists permit_type_labels cascade;
drop table if exists web_faq_entries cascade;
drop table if exists web_content_items cascade;
drop table if exists web_page_sections cascade;
drop table if exists events cascade;
drop table if exists resources cascade;
drop table if exists reviews cascade;
drop table if exists bulletin_comments cascade;

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

-- Drop every overload BY NAME rather than by signature.
--
-- The old list named a handful of signatures, which went stale the moment a
-- patch added a parameter: insert_quick_order alone ends up with 13-, 14-
-- and 15-argument overloads, and four functions below are created with a
-- plain `create function` (get_active_orders, insert_quick_order,
-- lookup_guest_order, set_order_status), so a surviving overload makes a
-- re-run fail with "function already exists with same argument types".
-- Dropping a table does not drop functions, so nothing else removes them.
--
-- Restricted to the names this file creates -- a blanket drop of every
-- function in `public` would take PostGIS with it, since that extension
-- installs there.
do $$
declare
  r record;
  v_names text[] := array[
      'account_deletion_blockers',
      'anonymize_account',
      'apply_incident_resolution',
      'auth_has_role',
      'auth_station_id',
      'catalog_caller_owns_station',
      'catalog_station_is_public',
      'confirm_jug_settlement',
      'container_types_sync_stations',
      'driver_leave_station',
      'driver_switch_station',
      'enforce_floor_price',
      'enforce_product_floor_price',
      'enforce_single_default_address',
      'flag_on_incident_filed',
      'generate_worker_code',
      'get_active_delivery_driver',
      'get_active_orders',
      'handle_new_auth_user',
      'hire_check_search',
      'hire_check_station_history',
      'insert_quick_order',
      'lookup_guest_order',
      'notify_accreditation_change',
      'notify_order_event',
      'notify_permit_review',
      'order_line_text',
      'owner_remove_worker',
      'peso_text',
      'prevent_owner_self_accreditation',
      'prevent_owner_self_permit_approval',
      'prevent_worker_self_credential_approval',
      'protect_order_financial_fields',
      'recompute_accreditation',
      'recompute_worker_clearance',
      'register_customer',
      'register_driver_for_station',
      'register_station_owner',
      'reject_jug_settlement',
      'set_accreditation_override',
      'set_comment_author_name',
      'set_order_status',
      'stamp_accredited_at',
      'stamp_accredited_at_insert',
      'station_products_sync_station',
      'station_products_touch_updated_at',
      'submit_station_review',
      'sync_required_permits',
      'sync_required_worker_credentials',
      'sync_station_from_products',
      'validate_bulletin_author'
  ];
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = any(v_names)
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

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

-- wasa_superadmin and station_staff were added by patch_roles_enum.sql;
-- declared here directly because a new enum value can't be used in the same
-- transaction that adds it, and this script runs as one.
create type app_role as enum ('wasa_admin', 'station_owner', 'driver', 'public_consumer', 'wasa_superadmin', 'station_staff');

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

-- `for all`, not `for insert`: PhotoService uploads with upsert, which RLS
-- also checks against SELECT and UPDATE (patch_bulletin_images_and_reference_rls.sql).
create policy bulletin_images_poster_write on storage.objects for all
  using (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  )
  with check (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );

-- Reference tables: read by anyone, written only by definer functions / SQL editor.
alter table associations enable row level security;
alter table barangays enable row level security;
create policy associations_public_read on associations for select using (true);
create policy barangays_public_read on barangays for select using (true);

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

-- ---------------------------------------------------------------------
-- supabase/migrations/0011_favorite_stations.sql
--
-- A customer's own shortlist of member stations. Purely a per-customer
-- preference -- it grants no access to anything and is never visible to
-- the station. The directory pins favourites above the distance-sorted
-- remainder, and the ordering screen prefers a favourite over the nearest
-- station.
-- ---------------------------------------------------------------------
create table if not exists favorite_stations (
  profile_id uuid not null references profiles(id) on delete cascade,
  station_id uuid not null references water_stations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, station_id)
);

create index if not exists favorite_stations_profile_idx on favorite_stations (profile_id);

alter table favorite_stations enable row level security;

drop policy if exists favorite_stations_self on favorite_stations;
create policy favorite_stations_self on favorite_stations for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());


-- ---------------------------------------------------------------------
-- supabase/patch_flagged_driver_rejoin.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a flagged driver could rejoin the association by re-registering.
--
-- There are two ways a driver joins a station, and only one of them
-- checked clearance:
--
--   driver_switch_station()        raises if clearance_status = 'flagged'
--   register_driver_for_station()  did not check at all
--
-- So the sequence below let a flagged driver straight back in:
--
--   1. Station A files an incident; a WASA admin confirms it, which sets
--      the worker's clearance_status to 'flagged'.
--   2. Station A removes the driver (owner_remove_worker), leaving
--      workers.station_id null.
--   3. The driver enters any station's invite code.
--   4. register_driver_for_station() takes its "previously left/removed"
--      re-link branch, which never looked at clearance, and adds them to
--      the new station's roster.
--
-- A driver who was NOT removed is blocked by driver_switch_station. Being
-- removed after an incident therefore made it easier to move, not harder
-- -- the opposite of what the worker security registry exists to do, and
-- the opposite of what the public website states:
--
--   "Maintains a shared worker security registry, so a driver flagged for
--    an incident at one station can't simply move to another unnoticed."
--
-- Found during the functionality evaluation of 10 October 2026, while
-- checking an evaluator's observation that the station invite code never
-- rotates -- which is what makes step 3 easy, since a removed driver
-- already knows it.
--
-- The check below is deliberately worded like the one in
-- driver_switch_station, so a flagged driver gets the same explanation
-- whichever route they try.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

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
  v_clearance clearance_status;
begin
  select id, station_id, clearance_status
    into v_worker_id, v_current_station_id, v_clearance
    from workers where profile_id = auth.uid();

  if v_worker_id is not null then
    if v_current_station_id is not null then
      return v_worker_id;
    end if;

    -- The fix. Checked only on the re-link branch: a brand new worker
    -- (further down) starts at 'pending_clearance', which must stay
    -- joinable or nobody could ever register in the first place.
    if v_clearance = 'flagged' then
      raise exception 'Cannot join a station while flagged. Contact WASA to resolve outstanding incidents.';
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

-- ---------------------------------------------------------------------
-- supabase/patch_overhaul_gaps.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Gaps found during the October 2026 evaluation and the UI overhaul.
--
-- Idempotent -- safe to run more than once. Run after every earlier patch
-- (it replaces notify_order_event and the incidents/bulletins read
-- policies). Each section says what was missing and why it matters.
--
--   1. Station invite codes could never be changed
--   2. Owners could read other stations' incident reports
--   3. No record of privacy-notice consent at sign-up
--   4. A driver had no way to report a failed delivery
--   5. Bulletin posts could not be reported or hidden
--   6. A flagged driver had no way to appeal
--   7. No audit log of who changed what
--   8. Website content edits could not be undone
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Notification categories used below.
-- ---------------------------------------------------------------------
alter table notifications drop constraint if exists notifications_category_check;
alter table notifications add constraint notifications_category_check
  check (category in ('order', 'permit', 'accreditation', 'account', 'worker', 'bulletin'));

-- ---------------------------------------------------------------------
-- 1. Regenerate a station's invite code.
--
-- The code was set once at registration and never changed. An evaluator
-- pointed out that a removed driver therefore always knows it -- which is
-- what made the flagged-driver rejoin (patch_flagged_driver_rejoin.sql)
-- easy. An owner can now issue a new code; the old one stops working.
-- Same alphabet and length as registration_screen.dart's generator.
-- ---------------------------------------------------------------------
create or replace function owner_regenerate_invite_code() returns text as $$
declare
  v_station_id uuid;
  v_code text;
  v_chars constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  i int;
begin
  select id into v_station_id from water_stations where owner_profile_id = auth.uid() limit 1;
  if v_station_id is null then
    raise exception 'Only a station owner can change the invite code.';
  end if;

  for attempt in 1..10 loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    begin
      update water_stations set invite_code = v_code where id = v_station_id;
      return v_code;
    exception when unique_violation then
      -- Another station already has this code; try another.
    end;
  end loop;
  raise exception 'Could not generate a unique code. Please try again.';
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function owner_regenerate_invite_code() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Incident privacy.
--
-- incidents_owner_read let an owner read every incident about any driver
-- currently on their roster -- including the full text of reports other
-- stations had filed before the driver moved. The registry's promise is
-- narrower: other stations learn *that* a driver is flagged (and how many
-- confirmed incidents), through hire_check_search, not what was written.
-- Owners now read the reports they filed; the driver can read the reports
-- about themselves (they need to, to appeal); officers read everything.
-- ---------------------------------------------------------------------
drop policy if exists incidents_owner_read on worker_incidents;
create policy incidents_owner_read on worker_incidents for select
  using (reported_by_profile_id = auth.uid());

drop policy if exists incidents_self_read on worker_incidents;
create policy incidents_self_read on worker_incidents for select
  using (worker_id in (select id from workers where profile_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 3. Privacy-notice consent.
--
-- Sign-up never recorded agreement to the privacy notice (RA 10173 expects
-- consent to be demonstrable). The app now requires the box to be ticked
-- and calls this once the account exists.
-- ---------------------------------------------------------------------
alter table profiles add column if not exists privacy_consented_at timestamptz;
alter table profiles add column if not exists privacy_notice_version text;

create or replace function record_privacy_consent(p_version text) returns void as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;
  update profiles
     set privacy_consented_at = now(), privacy_notice_version = p_version, updated_at = now()
   where id = auth.uid();
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function record_privacy_consent(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Failed deliveries.
--
-- A driver who couldn't deliver (nobody home, wrong address) had two
-- options: mark it delivered anyway, or leave it hanging. Now they report
-- it with a reason; the order goes back to the station's queue, unassigned,
-- so the owner can reassign or cancel it, and the customer is told why.
-- ---------------------------------------------------------------------
alter table orders add column if not exists failure_reason text;
alter table orders add column if not exists failed_at timestamptz;

create or replace function driver_report_failed_delivery(p_order_id uuid, p_reason text) returns void as $$
declare
  o orders%rowtype;
  v_worker_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Say why the delivery could not be completed.';
  end if;

  select id into v_worker_id from workers where profile_id = auth.uid();
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;
  if v_worker_id is null or o.driver_worker_id is distinct from v_worker_id then
    raise exception 'Only the assigned driver can report this delivery.';
  end if;
  if o.status not in ('assigned', 'active') then
    raise exception 'This order is not out for delivery.';
  end if;

  update orders
     set status = 'pending',
         driver_worker_id = null,
         failure_reason = trim(p_reason),
         failed_at = now()
   where id = p_order_id;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_report_failed_delivery(uuid, text) to authenticated;

-- notify_order_event, as in patch_notifications.sql, plus the failed
-- delivery case: the customer hears why, and the owner is asked to act.
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
  v_failed boolean;
begin
  select owner_profile_id, station_name into v_owner, v_station_name
    from water_stations where id = new.station_id;
  v_line := order_line_text(new.jugs_ordered, new.water_type, new.jug_type, new.product_kind);

  if tg_op = 'INSERT' then
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id);
    end if;
    return new;
  end if;

  v_failed := new.failed_at is not null and new.failed_at is distinct from old.failed_at;

  if v_failed then
    if new.customer_profile_id is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (new.customer_profile_id, 'order', 'Delivery attempt unsuccessful',
              coalesce(v_station_name, 'Your station') || ' · ' || new.failure_reason
                || '. The station will contact you or try again.',
              new.id, new.station_id);
    end if;
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'Delivery failed: reassign or cancel',
              v_line || ' · ' || new.failure_reason, new.id, new.station_id);
    end if;
  elsif new.status is distinct from old.status then
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
-- 5. Bulletin moderation.
--
-- Members can post and comment, but nobody could flag a post, and the only
-- moderation was outright deletion. Any signed-in member can now report a
-- post with a reason; officers see the reports and can hide a post (kept
-- for the record, gone from every feed) or unhide it.
-- ---------------------------------------------------------------------
alter table bulletins add column if not exists is_hidden boolean not null default false;
alter table bulletins add column if not exists hidden_by uuid references profiles(id) on delete set null;
alter table bulletins add column if not exists hidden_at timestamptz;

create table if not exists bulletin_reports (
  id uuid primary key default gen_random_uuid(),
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  reported_by uuid not null default auth.uid() references profiles(id) on delete cascade,
  reason text not null check (length(trim(reason)) > 0),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references profiles(id) on delete set null,
  unique (bulletin_id, reported_by)
);

create index if not exists bulletin_reports_open_idx on bulletin_reports (bulletin_id) where resolved_at is null;

alter table bulletin_reports enable row level security;

drop policy if exists bulletin_reports_insert on bulletin_reports;
create policy bulletin_reports_insert on bulletin_reports for insert
  with check (auth.uid() is not null and reported_by = auth.uid());

drop policy if exists bulletin_reports_read on bulletin_reports;
create policy bulletin_reports_read on bulletin_reports for select
  using (reported_by = auth.uid() or auth_has_role('wasa_admin'));

drop policy if exists bulletin_reports_admin_update on bulletin_reports;
create policy bulletin_reports_admin_update on bulletin_reports for update
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- Hidden posts drop out of every feed except for officers and the author.
drop policy if exists bulletins_public_read on bulletins;
create policy bulletins_public_read on bulletins for select
  using (not is_hidden or auth_has_role('wasa_admin') or posted_by = auth.uid());

-- ---------------------------------------------------------------------
-- 6. Driver appeals.
--
-- A confirmed incident flags a driver across every station, and there was
-- no way to contest it. The driver can now appeal a confirmed incident once,
-- in writing; officers uphold it or overturn it. Overturning dismisses the
-- incident, and apply_incident_resolution clears the flag if no other
-- confirmed incident remains.
-- ---------------------------------------------------------------------
alter table worker_incidents add column if not exists appeal_text text;
alter table worker_incidents add column if not exists appeal_status text;
alter table worker_incidents drop constraint if exists worker_incidents_appeal_status_check;
alter table worker_incidents add constraint worker_incidents_appeal_status_check
  check (appeal_status is null or appeal_status in ('pending', 'upheld', 'overturned'));
alter table worker_incidents add column if not exists appeal_submitted_at timestamptz;
alter table worker_incidents add column if not exists appeal_decided_at timestamptz;
alter table worker_incidents add column if not exists appeal_decided_by uuid references profiles(id) on delete set null;
alter table worker_incidents add column if not exists appeal_decision_note text;

create or replace function driver_submit_appeal(p_incident_id uuid, p_text text) returns void as $$
declare
  inc worker_incidents%rowtype;
  v_worker_name text;
begin
  if p_text is null or length(trim(p_text)) < 10 then
    raise exception 'Explain your appeal in a sentence or two.';
  end if;

  select * into inc from worker_incidents where id = p_incident_id for update;
  if not found or inc.worker_id not in (select id from workers where profile_id = auth.uid()) then
    raise exception 'Incident not found.';
  end if;
  if inc.status <> 'confirmed_flag' then
    raise exception 'Only a confirmed incident can be appealed.';
  end if;
  if inc.appeal_status is not null then
    raise exception 'This incident has already been appealed.';
  end if;

  update worker_incidents
     set appeal_text = trim(p_text), appeal_status = 'pending', appeal_submitted_at = now()
   where id = p_incident_id;

  select full_name into v_worker_name from workers where id = inc.worker_id;
  insert into notifications (profile_id, category, title, body)
  select m.profile_id, 'worker', 'Driver appeal to review', coalesce(v_worker_name, 'A driver') || ' has appealed a flag.'
    from memberships m
   where m.role = 'wasa_admin' and m.status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_submit_appeal(uuid, text) to authenticated;

create or replace function admin_decide_appeal(p_incident_id uuid, p_overturn boolean, p_note text) returns void as $$
declare
  inc worker_incidents%rowtype;
  v_driver_profile uuid;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can decide appeals.';
  end if;
  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'Give a reason for the decision.';
  end if;

  select * into inc from worker_incidents where id = p_incident_id for update;
  if not found or inc.appeal_status is distinct from 'pending' then
    raise exception 'There is no pending appeal on this incident.';
  end if;

  update worker_incidents
     set appeal_status = case when p_overturn then 'overturned' else 'upheld' end,
         appeal_decided_at = now(),
         appeal_decided_by = auth.uid(),
         appeal_decision_note = trim(p_note),
         status = case when p_overturn then 'dismissed'::incident_status else status end,
         resolved_by = case when p_overturn then auth.uid() else resolved_by end,
         resolved_at = case when p_overturn then now() else resolved_at end
   where id = p_incident_id;

  select profile_id into v_driver_profile from workers where id = inc.worker_id;
  if v_driver_profile is not null then
    insert into notifications (profile_id, category, title, body)
    values (v_driver_profile, 'worker',
            case when p_overturn then 'Your appeal was accepted' else 'Your appeal was not accepted' end,
            trim(p_note));
  end if;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function admin_decide_appeal(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Audit log.
--
-- The Activity page was assembled from reviewed_by/updated_by columns, so
-- it could only say who last touched a row -- not what changed, and nothing
-- at all for role changes or suspensions. audit_log records every change
-- to the records officers are accountable for, with before and after.
-- Written only by triggers; there is no insert, update or delete policy, so
-- nobody can edit or remove an entry from the app.
-- ---------------------------------------------------------------------
create table if not exists audit_log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid references profiles(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  summary text not null,
  before jsonb,
  after jsonb
);

create index if not exists audit_log_occurred_idx on audit_log (occurred_at desc);
create index if not exists audit_log_table_idx on audit_log (table_name, occurred_at desc);

alter table audit_log enable row level security;

drop policy if exists audit_log_admin_read on audit_log;
create policy audit_log_admin_read on audit_log for select
  using (auth_has_role('wasa_admin'));

create or replace function audit_row_change() returns trigger as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
  o jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  n jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_summary text;
begin
  v_summary := case tg_table_name
    when 'permits' then
      'Permit ' || replace(r->>'permit_type', '_', ' ') || ': ' || replace(coalesce(n->>'status', 'deleted'), '_', ' ')
    when 'water_stations' then
      'Station ' || coalesce(r->>'station_name', '') || ': accreditation '
        || replace(coalesce(n->>'accreditation_status', ''), '_', ' ')
    when 'memberships' then
      'Membership ' || coalesce(r->>'role', '') || ': '
        || case tg_op when 'INSERT' then 'added' when 'DELETE' then 'removed' else coalesce(n->>'status', '') end
    when 'worker_incidents' then
      'Incident ' || coalesce(r->>'incident_type', '') || ': ' || replace(coalesce(n->>'status', 'deleted'), '_', ' ')
        || case when n->>'appeal_status' is not null then ' (appeal ' || (n->>'appeal_status') || ')' else '' end
    when 'jug_settlements' then
      'Jug settlement of ' || coalesce(r->>'quantity', '?') || ': ' || coalesce(n->>'status', 'deleted')
    when 'bulletins' then
      'Bulletin "' || left(coalesce(r->>'title', ''), 60) || '": '
        || case when tg_op = 'DELETE' then 'deleted'
                when (n->>'is_hidden')::boolean then 'hidden'
                when (o->>'is_hidden')::boolean then 'unhidden'
                else 'updated' end
    else
      initcap(replace(tg_table_name, '_', ' ')) || ' ' || lower(tg_op)
  end;

  insert into audit_log (actor_id, action, table_name, record_id, summary, before, after)
  values (auth.uid(), lower(tg_op), tg_table_name, r->>'id', v_summary, o, n);
  return coalesce(new, old);
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_audit_permits on permits;
create trigger trg_audit_permits
  after update of status, expiry_date, is_required on permits
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_stations on water_stations;
create trigger trg_audit_stations
  after update of is_accredited, accreditation_status, owner_profile_id on water_stations
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_memberships on memberships;
create trigger trg_audit_memberships
  after insert or delete or update of role, status on memberships
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_incidents on worker_incidents;
create trigger trg_audit_incidents
  after insert or update of status, appeal_status on worker_incidents
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_settlements on jug_settlements;
create trigger trg_audit_settlements
  after insert or update of status on jug_settlements
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_bulletins on bulletins;
create trigger trg_audit_bulletins
  after delete or update of is_hidden, is_pinned on bulletins
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_sections on web_page_sections;
create trigger trg_audit_web_sections
  after insert or update or delete on web_page_sections
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_items on web_content_items;
create trigger trg_audit_web_items
  after insert or update or delete on web_content_items
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_faq on web_faq_entries;
create trigger trg_audit_web_faq
  after insert or update or delete on web_faq_entries
  for each row execute function audit_row_change();

-- ---------------------------------------------------------------------
-- 8. Website content history.
--
-- Saving a page section overwrote it for good. Every update or delete of
-- website content now keeps the previous version, and an officer can
-- restore one.
-- ---------------------------------------------------------------------
create table if not exists web_content_revisions (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid not null,
  snapshot jsonb not null,
  changed_by uuid references profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists web_content_revisions_record_idx on web_content_revisions (table_name, record_id, changed_at desc);

alter table web_content_revisions enable row level security;

drop policy if exists web_content_revisions_admin_read on web_content_revisions;
create policy web_content_revisions_admin_read on web_content_revisions for select
  using (auth_has_role('wasa_admin'));

create or replace function keep_web_content_revision() returns trigger as $$
begin
  insert into web_content_revisions (table_name, record_id, snapshot, changed_by)
  values (tg_table_name, old.id, to_jsonb(old), auth.uid());
  return coalesce(new, old);
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_revision_web_sections on web_page_sections;
create trigger trg_revision_web_sections
  before update or delete on web_page_sections
  for each row execute function keep_web_content_revision();

drop trigger if exists trg_revision_web_items on web_content_items;
create trigger trg_revision_web_items
  before update or delete on web_content_items
  for each row execute function keep_web_content_revision();

drop trigger if exists trg_revision_web_faq on web_faq_entries;
create trigger trg_revision_web_faq
  before update or delete on web_faq_entries
  for each row execute function keep_web_content_revision();

-- Puts a saved version back. A restore is itself an update, so the version
-- being replaced is kept too -- a restore can always be undone.
create or replace function restore_web_content_revision(p_revision_id bigint) returns void as $$
declare
  rev web_content_revisions%rowtype;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can restore website content.';
  end if;
  select * into rev from web_content_revisions where id = p_revision_id;
  if not found then
    raise exception 'That version no longer exists.';
  end if;

  if rev.table_name = 'web_page_sections' then
    update web_page_sections
       set title = rev.snapshot->>'title', body = rev.snapshot->>'body',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  elsif rev.table_name = 'web_content_items' then
    update web_content_items
       set title = rev.snapshot->>'title', body = rev.snapshot->>'body', icon = rev.snapshot->>'icon',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  elsif rev.table_name = 'web_faq_entries' then
    update web_faq_entries
       set question = rev.snapshot->>'question', answer = rev.snapshot->>'answer',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  else
    raise exception 'Unknown content type.';
  end if;

  if not found then
    raise exception 'The item this version belonged to has been deleted.';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function restore_web_content_revision(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_advisor_hardening.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Hardening from Supabase's security advisor, 17 October 2026.
--
-- Idempotent -- safe to run more than once. Run after every earlier patch.
--
-- 1. Jug balances were readable by anyone holding the publishable key.
--
--    jug_balances is a view over jug_ledger_entries. Views run with their
--    creator's rights by default, which skips the ledger's RLS -- so
--    `select * from jug_balances` with the key that ships in every APK and
--    web build returned every station's balances with every other station,
--    signed in or not. The ledger's own policies already say who should see
--    what (an owner: rows their station is part of; officers: everything),
--    so the view now runs with the caller's rights and those policies apply.
--    The clearinghouse screen already filters to the owner's station, so it
--    sees exactly what it did before. Drivers never read this view.
--
--    bulletin_reaction_counts gets the same switch. Reactions are publicly
--    readable anyway, so nothing changes for anyone; it just stops being an
--    exception to RLS.
--
--    public_stations deliberately stays as it is: it is the public
--    directory -- a fixed set of columns from accredited, active stations --
--    and water_stations' RLS rightly hides those rows from visitors.
--
-- 2. Seven functions did not pin search_path.
--
--    Without it a function resolves table and function names through the
--    caller's search_path, which a caller can change. Pinned to public,
--    matching every security definer function in this project.
--
-- 3. sync_station_from_products() could be called by anyone.
--
--    It recomputes a station's prices and water types from its products,
--    and is meant to run only from the two triggers that call it (both
--    security definer, so they keep the right to). Called directly it
--    did no harm beyond needless work, but it has no reason to be public.
-- =====================================================================

-- 1.
alter view jug_balances set (security_invoker = true);
alter view bulletin_reaction_counts set (security_invoker = true);

-- 2.
alter function get_pending_orders(uuid) set search_path = public;
alter function get_active_orders(uuid) set search_path = public;
alter function generate_worker_code() set search_path = public;
alter function peso_text(numeric) set search_path = public;
alter function stamp_accredited_at() set search_path = public;
alter function stamp_accredited_at_insert() set search_path = public;
alter function station_products_touch_updated_at() set search_path = public;

-- 3.
revoke execute on function sync_station_from_products(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_failed_delivery_fix.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a driver's "Couldn't deliver" always failed.
--
-- driver_report_failed_delivery() (patch_overhaul_gaps.sql) puts the order
-- back in the station's queue by clearing driver_worker_id. The older
-- protect_order_financial_fields trigger (patch_audit_remediation.sql)
-- refuses any change to driver_worker_id unless the signed-in user is an
-- owner or an officer -- and it looks at who is signed in, not at which
-- function is doing the update, so it refused the driver's own report:
--
--   "Drivers may not modify order financial, product, station, or
--    assignment details."
--
-- Found by running the test case GTW-APP-314 against the live database on
-- 17 October 2026. Starting and completing a delivery were unaffected:
-- neither touches driver_worker_id.
--
-- The trigger still guards every direct write. It now also lets through an
-- update that driver_report_failed_delivery() has vouched for, by setting
-- a transaction-local flag around its one update. Clients can't set that
-- flag: they reach the database only through PostgREST, which exposes the
-- public schema's tables and functions, not set_config().
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function protect_order_financial_fields() returns trigger as $$
begin
  -- An update a trusted function has already checked (see above).
  if current_setting('gentri.trusted_order_change', true) = 'on' then
    return new;
  end if;

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

create or replace function driver_report_failed_delivery(p_order_id uuid, p_reason text) returns void as $$
declare
  o orders%rowtype;
  v_worker_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Say why the delivery could not be completed.';
  end if;

  select id into v_worker_id from workers where profile_id = auth.uid();
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;
  if v_worker_id is null or o.driver_worker_id is distinct from v_worker_id then
    raise exception 'Only the assigned driver can report this delivery.';
  end if;
  if o.status not in ('assigned', 'active') then
    raise exception 'This order is not out for delivery.';
  end if;

  -- Checked above, so vouch for this one update to
  -- protect_order_financial_fields, then withdraw it.
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders
     set status = 'pending',
         driver_worker_id = null,
         failure_reason = trim(p_reason),
         failed_at = now()
   where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_report_failed_delivery(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_signed_in_ordering.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Ordering requires a signed-in customer account -- on the server too.
--
-- The app stopped offering guest checkout some time ago: the order form
-- shows a sign-in gate to visitors (quick_order_screen.dart), so every order
-- is tied to a real account. The server never followed. insert_quick_order
-- still accepted calls from signed-out visitors, holding nothing but the
-- publishable key that ships in every APK and web build, and stored them as
-- guest orders -- so anyone could skip the app and send stations orders that
-- no account stood behind.
--
-- This patch:
--
--   1. insert_quick_order refuses anyone who isn't a signed-in, active
--      customer, and records the order against that account. p_guest_name
--      and p_guest_phone keep their places in the signature so the app
--      doesn't break mid-update; p_guest_phone now only carries the contact
--      number for the delivery (orders.customer_phone), as it already did
--      for signed-in orders.
--
--   2. The guest-tracking path goes. A guest could look an order up, follow
--      its driver on the map and cancel it with the order ID and checkout
--      phone number. With no new guest orders that path only served three
--      old, closed orders (the last placed 11 September 2026), so:
--        - get_active_delivery_driver answers only the customer who placed
--          the order;
--        - lookup_guest_order is no longer callable from the app;
--        - signed-out visitors can no longer call set_order_status, whose
--          guest-cancel branch they were the only route into.
--
-- The old guest orders stay in the database, unchanged, for the record.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- 1.
create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total_amount numeric,
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
  v_max_qty constant integer := 50;
begin
  if auth.uid() is null then
    raise exception 'Sign in to place an order.';
  end if;
  if not auth_has_role('public_consumer') then
    raise exception 'Only customer accounts can place orders.';
  end if;

  if p_client_request_id is not null then
    -- A retried submit returns the order it already created -- but only
    -- the caller's own, so a request id can't fish out someone else's.
    select id into new_order_id from orders
     where client_request_id = p_client_request_id and customer_profile_id = auth.uid();
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
    p_station_id, auth.uid(), null, null,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p.water_type, p.container_code,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin, p.id, p.price, p.kind
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- 2.
create or replace function get_active_delivery_driver(p_order_id uuid, p_guest_phone text default null)
returns table(driver_name text, driver_phone text, lat double precision, lng double precision, last_updated timestamptz)
as $$
declare
  v_order orders%rowtype;
begin
  -- p_guest_phone is ignored; it stays in the signature for older builds.
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found.';
  end if;

  if auth.uid() is null or v_order.customer_profile_id is distinct from auth.uid() then
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

revoke execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) from public, anon;
grant execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) to authenticated;

revoke execute on function get_active_delivery_driver(uuid, text) from public, anon;
grant execute on function get_active_delivery_driver(uuid, text) to authenticated;

revoke execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) from public, anon;
grant execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) to authenticated;

revoke execute on function lookup_guest_order(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_roles_governance.sql (patch_roles_enum.sql is folded into
-- the app_role definition above)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Roles and governance (UI/Roles plan, Phase 2). Run after
-- patch_roles_enum.sql. Idempotent -- safe to run more than once.
--
--  1. Super admins pass every officer check, plus their own powers.
--  2. Officer accounts are protected: only a super admin may create,
--     suspend, demote or change any role, nobody may suspend or demote
--     their own officer account, and the last active super admin can't be
--     removed -- so no single account can lock the association out.
--  3. A super admin can promote an existing account to officer (by email),
--     demote one, and transfer a station to a new owner.
--  4. Separation of duties: an officer linked to a station (owner, staff
--     or driver there) can't review its permits, change its accreditation
--     or decide incidents about it.
--  5. Association settings: the grace period before a station lapses, and
--     how long an invite code stays valid.
--  6. Station staff: owners invite them with their own code; staff can
--     read their station's orders, drivers and tracking and run orders
--     through set_order_status like the owner. Nothing else.
--  7. Invite codes expire (driver and staff) and are renewed by the owner.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Roles
-- ---------------------------------------------------------------------
create or replace function auth_has_role(check_role app_role) returns boolean
language sql stable security definer set search_path = public as $$
  -- A super admin holds every officer power, so asking "is this an
  -- officer?" is true for them as well. All 44 officer policies use this.
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid()
      and m.status = 'active'
      and (m.role = check_role or (check_role = 'wasa_admin' and m.role = 'wasa_superadmin'))
  );
$$;

create or replace function auth_is_superadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid() and m.status = 'active' and m.role = 'wasa_superadmin'
  );
$$;

-- The station a staff member works at. Deliberately separate from
-- auth_station_id(): that one also decides who may confirm a jug
-- settlement, which staff must not do.
create or replace function auth_staff_station_id() returns uuid
language sql stable security definer set search_path = public as $$
  select m.station_id from memberships m
  where m.profile_id = auth.uid() and m.role = 'station_staff' and m.status = 'active'
  limit 1;
$$;

-- Is the signed-in person linked to this station in any working role?
create or replace function auth_linked_to_station(p_station_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p_station_id is not null and (
    exists (select 1 from water_stations where id = p_station_id and owner_profile_id = auth.uid())
    or exists (select 1 from memberships where profile_id = auth.uid() and station_id = p_station_id and status = 'active')
    or exists (select 1 from workers where profile_id = auth.uid() and station_id = p_station_id)
  );
$$;

grant execute on function auth_is_superadmin() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Officer accounts are protected
-- ---------------------------------------------------------------------
create or replace function guard_membership_change() returns trigger as $$
declare
  v_actor uuid := auth.uid();
  v_old_officer boolean := tg_op <> 'INSERT' and old.role in ('wasa_admin', 'wasa_superadmin');
  v_new_officer boolean := tg_op <> 'DELETE' and new.role in ('wasa_admin', 'wasa_superadmin');
  v_role_changed boolean := tg_op = 'UPDATE' and new.role is distinct from old.role;
  v_remaining int;
begin
  -- The SQL Editor, seed scripts and server functions run with no signed-in
  -- user; they are trusted.
  if v_actor is null then
    return coalesce(new, old);
  end if;

  if (v_old_officer or v_new_officer or v_role_changed) and not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can create, change or suspend officer accounts, or change anyone''s role.';
  end if;

  if tg_op <> 'INSERT' and v_old_officer and old.profile_id = v_actor
     and (tg_op = 'DELETE' or new.status <> 'active' or v_role_changed) then
    raise exception 'You can''t suspend, remove or demote your own officer account. Ask another super admin.';
  end if;

  if tg_op <> 'INSERT' and old.role = 'wasa_superadmin' and old.status = 'active'
     and (tg_op = 'DELETE' or new.role <> 'wasa_superadmin' or new.status <> 'active') then
    select count(*) into v_remaining from memberships
     where role = 'wasa_superadmin' and status = 'active' and id <> old.id;
    if v_remaining = 0 then
      raise exception 'There must always be at least one active super admin.';
    end if;
  end if;

  return coalesce(new, old);
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_membership_change') then
    create trigger trg_guard_membership_change
      before insert or update or delete on memberships
      for each row execute function guard_membership_change();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Super admin tools
-- ---------------------------------------------------------------------
create or replace function superadmin_find_account(p_email text)
returns table (profile_id uuid, full_name text, email text, role text, status text, station_name text)
as $$
begin
  if not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can look up accounts by email.';
  end if;
  return query
    select u.id, p.full_name, u.email::text, m.role::text, m.status, ws.station_name
      from auth.users u
      left join profiles p on p.id = u.id
      left join memberships m on m.profile_id = u.id
      left join water_stations ws on ws.id = m.station_id
     where lower(u.email) = lower(trim(p_email));
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function superadmin_find_account(text) to authenticated;

create or replace function superadmin_set_role(p_profile uuid, p_role app_role) returns void as $$
declare
  m memberships%rowtype;
  v_association uuid;
begin
  if not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can change officer roles.';
  end if;
  if p_role not in ('wasa_admin', 'wasa_superadmin', 'public_consumer') then
    raise exception 'Use this to make an account an officer or super admin, or to return an officer to a customer account.';
  end if;

  select * into m from memberships where profile_id = p_profile limit 1;

  -- Separation of duties: officers decide on stations, so an officer may
  -- not also own, staff or drive for one.
  if m.id is not null and m.role in ('station_owner', 'station_staff', 'driver') and p_role <> 'public_consumer' then
    raise exception 'This account works for a station. Officers need an account of their own, so no one reviews their own station.';
  end if;

  if m.id is null then
    select id into v_association from associations limit 1;
    insert into memberships (profile_id, association_id, role, status) values (p_profile, v_association, p_role, 'active');
  else
    update memberships set role = p_role, station_id = null, status = 'active' where id = m.id;
  end if;

  insert into notifications (profile_id, category, title, body)
  values (p_profile, 'account',
          case p_role
            when 'wasa_superadmin' then 'You are now a WASA super admin'
            when 'wasa_admin' then 'You are now a WASA officer'
            else 'Your officer access has ended'
          end,
          case when p_role = 'public_consumer'
               then 'Your account is now a customer account.'
               else 'Sign in to the admin portal to start.' end);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function superadmin_set_role(uuid, app_role) to authenticated;

create or replace function superadmin_transfer_station(p_station_id uuid, p_new_owner uuid) returns void as $$
declare
  s water_stations%rowtype;
  v_new memberships%rowtype;
begin
  if not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can transfer a station.';
  end if;
  select * into s from water_stations where id = p_station_id for update;
  if not found then
    raise exception 'Station not found.';
  end if;
  if s.owner_profile_id = p_new_owner then
    raise exception 'That account already owns this station.';
  end if;

  select * into v_new from memberships where profile_id = p_new_owner limit 1;
  if v_new.id is not null and v_new.role <> 'public_consumer' then
    raise exception 'The new owner must be a customer account with no other role (not an officer, owner, staff member or driver).';
  end if;

  -- The station keeps everything -- orders, permits, jug balances, staff,
  -- drivers. Only who owns it changes.
  update water_stations set owner_profile_id = p_new_owner, updated_at = now() where id = p_station_id;

  if s.owner_profile_id is not null then
    update memberships set role = 'public_consumer', station_id = null
     where profile_id = s.owner_profile_id and role = 'station_owner';
    insert into notifications (profile_id, category, title, body, station_id)
    values (s.owner_profile_id, 'account', 'Station ownership transferred',
            s.station_name || ' now belongs to another account. Your account is now a customer account.', p_station_id);
  end if;

  if v_new.id is null then
    insert into memberships (profile_id, association_id, role, station_id, status)
    values (p_new_owner, s.association_id, 'station_owner', p_station_id, 'active');
  else
    update memberships set role = 'station_owner', station_id = p_station_id, status = 'active' where id = v_new.id;
  end if;

  insert into notifications (profile_id, category, title, body, station_id)
  values (p_new_owner, 'account', 'You now own ' || s.station_name,
          'WASA transferred the station to your account. Sign in to the station portal.', p_station_id);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function superadmin_transfer_station(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Separation of duties
-- ---------------------------------------------------------------------
create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if (new.status = 'approved' and new.status is distinct from old.status)
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  elsif auth.uid() is not null
        and (new.status is distinct from old.status or new.expiry_date is distinct from old.expiry_date
             or new.is_required is distinct from old.is_required)
        and auth_linked_to_station(new.station_id) then
    raise exception 'You are linked to this station, so another officer must review its permits.';
  end if;
  return new;
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
  elsif auth.uid() is not null
        and (new.is_accredited is distinct from old.is_accredited
             or new.accreditation_override_by is distinct from old.accreditation_override_by
             or new.is_active is distinct from old.is_active)
        and auth_linked_to_station(new.id) then
    raise exception 'You are linked to this station, so another officer must decide its accreditation.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function prevent_conflicted_incident_decision() returns trigger as $$
declare
  v_reporting_station uuid;
  v_worker_station uuid;
begin
  if auth.uid() is null or not auth_has_role('wasa_admin') then
    return new;
  end if;
  if new.status is not distinct from old.status and new.appeal_status is not distinct from old.appeal_status then
    return new;
  end if;
  select id into v_reporting_station from water_stations where owner_profile_id = new.reported_by_profile_id limit 1;
  select station_id into v_worker_station from workers where id = new.worker_id;
  if auth_linked_to_station(v_reporting_station) or auth_linked_to_station(v_worker_station) then
    raise exception 'You are linked to a station in this incident, so another officer must decide it.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_prevent_conflicted_incident_decision') then
    create trigger trg_prevent_conflicted_incident_decision
      before update on worker_incidents
      for each row execute function prevent_conflicted_incident_decision();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Association settings
-- ---------------------------------------------------------------------
create table if not exists association_settings (
  id boolean primary key default true check (id),
  grace_days int not null default 30 check (grace_days between 0 and 365),
  invite_valid_days int not null default 7 check (invite_valid_days between 1 and 90),
  updated_by uuid references profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into association_settings (id) values (true) on conflict (id) do nothing;

alter table association_settings enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'association_settings' and policyname = 'association_settings_read') then
    create policy association_settings_read on association_settings for select using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'association_settings' and policyname = 'association_settings_superadmin_update') then
    create policy association_settings_superadmin_update on association_settings for update
      using (auth_is_superadmin()) with check (auth_is_superadmin());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6 & 7. Station staff, and invite codes that expire
-- ---------------------------------------------------------------------
alter table water_stations add column if not exists invite_code_expires_at timestamptz;
alter table water_stations add column if not exists staff_invite_code text;
alter table water_stations add column if not exists staff_invite_expires_at timestamptz;
create unique index if not exists water_stations_staff_invite_code_key on water_stations (staff_invite_code);

create or replace function new_invite_code() returns text as $$
declare
  v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- no 0/O or 1/I look-alikes
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    exit when not exists (select 1 from water_stations where invite_code = v_code or staff_invite_code = v_code);
  end loop;
  return v_code;
end;
$$ language plpgsql volatile set search_path = public;

create or replace function invite_valid_until() returns timestamptz
language sql stable set search_path = public as $$
  select now() + make_interval(days => coalesce((select invite_valid_days from association_settings limit 1), 7));
$$;

create or replace function owner_regenerate_invite_code() returns text as $$
declare
  v_station_id uuid;
  v_code text := new_invite_code();
begin
  select id into v_station_id from water_stations where owner_profile_id = auth.uid() limit 1;
  if v_station_id is null then
    raise exception 'Only a station owner can change the invite code.';
  end if;
  update water_stations set invite_code = v_code, invite_code_expires_at = invite_valid_until() where id = v_station_id;
  return v_code;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function owner_regenerate_staff_code() returns text as $$
declare
  v_station_id uuid;
  v_code text := new_invite_code();
begin
  select id into v_station_id from water_stations where owner_profile_id = auth.uid() limit 1;
  if v_station_id is null then
    raise exception 'Only a station owner can issue a staff code.';
  end if;
  update water_stations set staff_invite_code = v_code, staff_invite_expires_at = invite_valid_until() where id = v_station_id;
  return v_code;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function owner_regenerate_invite_code() to authenticated;
grant execute on function owner_regenerate_staff_code() to authenticated;

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
  v_expires timestamptz;
  v_worker_id uuid;
  v_current_station_id uuid;
  v_clearance clearance_status;
begin
  select id, station_id, clearance_status
    into v_worker_id, v_current_station_id, v_clearance
    from workers where profile_id = auth.uid();

  if v_worker_id is not null and v_current_station_id is not null then
    return v_worker_id;
  end if;

  select id, association_id, invite_code_expires_at into v_station_id, v_association_id, v_expires
    from water_stations where invite_code ilike p_invite_code;
  if v_station_id is null then
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  if v_worker_id is not null then
    -- Previously left/removed from a station: re-link -- unless flagged
    -- (patch_flagged_driver_rejoin.sql).
    if v_clearance = 'flagged' then
      raise exception 'Cannot join a station while flagged. Contact WASA to resolve outstanding incidents.';
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
  v_expires timestamptz;
begin
  select id, clearance_status into v_worker_id, v_clearance from workers where profile_id = auth.uid();
  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;
  if v_clearance = 'flagged' then
    raise exception 'Cannot switch stations while flagged. Contact WASA to resolve outstanding incidents.';
  end if;

  select id, association_id, invite_code_expires_at into v_new_station_id, v_association_id, v_expires
    from water_stations where invite_code ilike p_invite_code;
  if v_new_station_id is null then
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
  -- Returning unfinished orders to the queue changes their driver; the
  -- order trigger allows it for this trusted function.
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');
  perform set_config('gentri.trusted_order_change', 'off', true);
  update workers set station_id = v_new_station_id, updated_at = now() where id = v_worker_id;
  update memberships set station_id = v_new_station_id, association_id = v_association_id
    where profile_id = auth.uid() and role = 'driver';
  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_new_station_id);
end;
$$ language plpgsql security definer set search_path = public;

create or replace function register_staff_for_station(p_staff_code text, p_full_name text, p_phone_number text)
returns uuid as $$
declare
  v_station_id uuid;
  v_association_id uuid;
  v_expires timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  select station_id into v_station_id from memberships
   where profile_id = auth.uid() and role = 'station_staff' and status = 'active';
  if v_station_id is not null then
    return v_station_id;
  end if;
  if exists (select 1 from memberships where profile_id = auth.uid() and status = 'active') then
    raise exception 'This account already has a different role. Sign out and use a different email, or contact WASA.';
  end if;

  select id, association_id, staff_invite_expires_at into v_station_id, v_association_id, v_expires
    from water_stations where staff_invite_code ilike trim(p_staff_code);
  if v_station_id is null then
    raise exception 'Invalid staff code. Ask the station owner for the staff code (not the driver code).';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This staff code has expired. Ask the station owner for a new one.';
  end if;

  -- Normally created at sign-up (handle_new_auth_user); made here too so an
  -- account that somehow lacks one can still join.
  insert into profiles (id, full_name, phone_number)
  values (auth.uid(), coalesce(nullif(trim(p_full_name), ''), ''), nullif(trim(p_phone_number), ''))
  on conflict (id) do update
    set full_name = coalesce(nullif(trim(excluded.full_name), ''), profiles.full_name),
        phone_number = coalesce(excluded.phone_number, profiles.phone_number),
        updated_at = now();

  -- A revoked staff row from an earlier job is reused rather than doubled.
  update memberships set role = 'station_staff', station_id = v_station_id, association_id = v_association_id, status = 'active'
   where profile_id = auth.uid() and role = 'station_staff';
  if not found then
    insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'station_staff', v_station_id);
  end if;

  insert into notifications (profile_id, category, title, body, station_id)
  select ws.owner_profile_id, 'account', 'New staff member',
         coalesce(nullif(trim(p_full_name), ''), 'Someone') || ' joined your station as staff.', ws.id
    from water_stations ws where ws.id = v_station_id and ws.owner_profile_id is not null;
  return v_station_id;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function register_staff_for_station(text, text, text) to authenticated;

-- The owner's team list: names and phones live in profiles, which owners
-- can't otherwise read.
create or replace function owner_list_staff()
returns table (profile_id uuid, full_name text, phone_number text, status text, joined_at timestamptz)
as $$
begin
  return query
    select m.profile_id, p.full_name, p.phone_number, m.status, m.created_at
      from memberships m
      join profiles p on p.id = m.profile_id
      join water_stations ws on ws.id = m.station_id
     where ws.owner_profile_id = auth.uid() and m.role = 'station_staff' and m.status = 'active'
     order by p.full_name;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function owner_remove_staff(p_profile uuid) returns void as $$
begin
  update memberships m set status = 'revoked'
    from water_stations ws
   where ws.id = m.station_id and ws.owner_profile_id = auth.uid()
     and m.profile_id = p_profile and m.role = 'station_staff';
  if not found then
    raise exception 'That person is not on your station''s staff.';
  end if;
  insert into notifications (profile_id, category, title, body)
  values (p_profile, 'account', 'Staff access ended', 'The station owner removed your staff access.');
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function owner_list_staff() to authenticated;
grant execute on function owner_remove_staff(uuid) to authenticated;

-- What staff may read: their station, its orders, drivers and tracking.
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'water_stations' and policyname = 'stations_staff_read') then
    create policy stations_staff_read on water_stations for select using (id = auth_staff_station_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'orders' and policyname = 'orders_staff_read') then
    create policy orders_staff_read on orders for select using (station_id = auth_staff_station_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'workers' and policyname = 'workers_staff_read') then
    create policy workers_staff_read on workers for select using (station_id = auth_staff_station_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'driver_states' and policyname = 'driver_states_staff_read') then
    create policy driver_states_staff_read on driver_states for select using (station_id = auth_staff_station_id());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'station_products' and policyname = 'station_products_staff_read') then
    create policy station_products_staff_read on station_products for select using (station_id = auth_staff_station_id());
  end if;
end $$;

-- Staff run orders like the owner: assign, unassign, cancel.
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
  v_is_station_side boolean;
  v_new_driver_station_id uuid;
  v_new_driver_clearance clearance_status;
begin
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  v_is_station_side := auth_has_role('wasa_admin')
    or exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid())
    or (auth_staff_station_id() is not null and auth_staff_station_id() = o.station_id);

  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  if v_is_station_side then
    -- Station-side changes to the assignment are checked here, so the
    -- order trigger (which guards direct writes) is told to allow them --
    -- staff aren't owners in its eyes.
    perform set_config('gentri.trusted_order_change', 'on', true);
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
    elsif o.status in ('pending', 'assigned') and p_new_status = 'cancelled' then
      update orders set status = 'cancelled' where id = p_order_id;
    elsif o.status = 'assigned' and p_new_status = 'pending' then
      update orders set status = 'pending', driver_worker_id = null where id = p_order_id;
    else
      perform set_config('gentri.trusted_order_change', 'off', true);
      raise exception 'Not a valid status change for the station.';
    end if;
    perform set_config('gentri.trusted_order_change', 'off', true);
    return;
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

revoke execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) from public, anon;
grant execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) to authenticated;

-- New orders and failed deliveries also reach the station's staff.
create or replace function notify_order_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_station_name text;
  v_driver_profile uuid;
  v_line text;
  v_failed boolean;
begin
  select owner_profile_id, station_name into v_owner, v_station_name
    from water_stations where id = new.station_id;
  v_line := order_line_text(new.jugs_ordered, new.water_type, new.jug_type, new.product_kind);

  if tg_op = 'INSERT' then
    insert into notifications (profile_id, category, title, body, order_id, station_id)
    select p, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id
      from (select v_owner as p
            union
            select m.profile_id from memberships m
             where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
     where p is not null;
    return new;
  end if;

  v_failed := new.failed_at is not null and new.failed_at is distinct from old.failed_at;

  if v_failed then
    if new.customer_profile_id is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (new.customer_profile_id, 'order', 'Delivery attempt unsuccessful',
              coalesce(v_station_name, 'Your station') || ' · ' || new.failure_reason
                || '. The station will contact you or try again.',
              new.id, new.station_id);
    end if;
    insert into notifications (profile_id, category, title, body, order_id, station_id)
    select p, 'order', 'Delivery failed: reassign or cancel', v_line || ' · ' || new.failure_reason, new.id, new.station_id
      from (select v_owner as p
            union
            select m.profile_id from memberships m
             where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
     where p is not null;
  elsif new.status is distinct from old.status then
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

-- ---------------------------------------------------------------------
-- supabase/patch_compliance.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Compliance automation, official notices and compliance cases
-- (UI/Roles plan Phase 3, Rollout plan "Fighting non-compliance").
-- Run after patch_roles_governance.sql. Idempotent.
--
--  1. Each permit type has a validity (the water test is monthly) and a
--     plain-language description for the owner's checklist. Approving a
--     permit with no expiry set gives it review date + validity; the
--     officer's own date still wins.
--  2. Driver licences carry an expiry date too.
--  3. Every station has a standing, worked out the same way for everyone:
--       applicant  never accredited yet
--       good       accredited, nothing expired
--       warning    a required permit expired, still within the grace period
--                  (or a renewal is waiting for review)
--       lapsed     a required permit expired past the grace period: the
--                  Accredited badge comes off. The station can still take
--                  orders (board decision, 18 Oct 2026) and is shown as
--                  Lapsed.
--       suspended  closed by WASA
--     The grace period is association_settings.grace_days (set by a super
--     admin).
--  4. A daily job (pg_cron, 06:00 Philippine time) sends reminders 30 and
--     7 days before a permit or licence expires and when it does, then
--     re-works every station's standing. Each reminder is sent once.
--  5. Official notices from WASA to one station or all, with read and
--     acknowledgement receipts.
--  6. Compliance cases: a written record of each issue (permit, water test,
--     conduct, complaint -- never price), the decision, the officer and the
--     station's written response.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Permit validity and descriptions
-- ---------------------------------------------------------------------
alter table permit_type_labels add column if not exists validity_months int check (validity_months is null or validity_months > 0);
alter table permit_type_labels add column if not exists description text;

update permit_type_labels l set
  validity_months = coalesce(l.validity_months, v.months),
  description = coalesce(l.description, v.description)
from (values
  ('business_permit', 12, 'The city''s permit to operate a business. Renewed every year, usually in January.'),
  ('sanitary_permit', 12, 'Issued by the City Health Office after an inspection of the station. Renewed yearly.'),
  ('fda_license', 24, 'FDA License to Operate for a water refilling station.'),
  ('fire_safety_certificate', 12, 'Fire Safety Inspection Certificate from the Bureau of Fire Protection. Yearly.'),
  ('water_quality_test_report', 1, 'Monthly bacteriological test of your water by a DOH-accredited laboratory. Upload each month''s result.'),
  ('operator_training_certificate', null, 'Certificate from the operator''s water safety training. Replace it if the operator changes.'),
  ('alkaline_tech_cert', null, 'Technical certification of the alkaline machine. Only for stations selling alkaline water.'),
  ('alkaline_water_test', 6, 'Quality test of the alkaline water, every six months. Only for stations selling alkaline water.'),
  ('nwrb_water_permit', null, 'National Water Resources Board permit for the water source.'),
  ('nwrb_certificate_of_public_convenience', null, 'National Water Resources Board Certificate of Public Convenience.')
) as v(permit_type, months, description)
where l.permit_type::text = v.permit_type;

create or replace function permit_default_expiry() returns trigger as $$
declare
  v_months int;
begin
  if new.status = 'approved' and new.status is distinct from old.status and new.expiry_date is null then
    select validity_months into v_months from permit_type_labels where permit_type = new.permit_type;
    if v_months is not null then
      new.expiry_date := (current_date + make_interval(months => v_months))::date;
    end if;
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_permit_default_expiry') then
    create trigger trg_permit_default_expiry before update on permits
      for each row execute function permit_default_expiry();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Licence expiry
-- ---------------------------------------------------------------------
alter table worker_credentials add column if not exists expiry_date date;

-- ---------------------------------------------------------------------
-- 3. Standing
-- ---------------------------------------------------------------------
alter table water_stations add column if not exists standing text not null default 'applicant';
alter table water_stations add column if not exists standing_since timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'water_stations_standing_check') then
    alter table water_stations add constraint water_stations_standing_check
      check (standing in ('applicant', 'good', 'warning', 'lapsed', 'suspended'));
  end if;
end $$;

create or replace function compliance_grace_days() returns int
language sql stable set search_path = public as $$
  select coalesce((select grace_days from association_settings limit 1), 30);
$$;

-- Re-works one station's accreditation and standing and tells the owner
-- (and, on a lapse, the officers) when the standing changes. Called by the
-- permit trigger and by the daily job.
create or replace function refresh_station_compliance(p_station_id uuid) returns void as $$
declare
  s water_stations%rowtype;
  v_grace int := compliance_grace_days();
  v_all_ok boolean;
  v_expired_any boolean;
  v_expired_past_grace boolean;
  v_standing text;
begin
  select * into s from water_stations where id = p_station_id;
  if not found then
    return;
  end if;

  -- An approved permit counts until it is past expiry + grace.
  select not exists (
    select 1 from permits
     where station_id = p_station_id and is_required
       and (status <> 'approved' or (expiry_date is not null and expiry_date < current_date - v_grace))
  ) into v_all_ok;

  select exists (select 1 from permits where station_id = p_station_id and is_required and status = 'approved'
                   and expiry_date is not null and expiry_date < current_date),
         exists (select 1 from permits where station_id = p_station_id and is_required and status = 'approved'
                   and expiry_date is not null and expiry_date < current_date - v_grace)
    into v_expired_any, v_expired_past_grace;

  if s.accreditation_override_by is null then
    update water_stations
       set is_accredited = v_all_ok,
           accreditation_status = case
             when v_all_ok then 'accredited'
             when accreditation_status = 'accredited' then 'under_review'
             else accreditation_status
           end,
           updated_at = now()
     where id = p_station_id
       and (is_accredited is distinct from v_all_ok
            or (v_all_ok and accreditation_status <> 'accredited')
            or (not v_all_ok and accreditation_status = 'accredited'));
    select * into s from water_stations where id = p_station_id;
  end if;

  v_standing := case
    when not s.is_active or s.accreditation_status = 'suspended' then 'suspended'
    when v_expired_past_grace and s.accreditation_override_by is null then 'lapsed'
    when v_expired_any then 'warning'
    when s.is_accredited then 'good'
    when s.accredited_at is not null then 'warning'
    else 'applicant'
  end;

  if v_standing is distinct from s.standing then
    update water_stations set standing = v_standing, standing_since = now() where id = p_station_id;

    if s.owner_profile_id is not null and v_standing in ('good', 'warning', 'lapsed') then
      insert into notifications (profile_id, category, title, body, station_id)
      values (s.owner_profile_id, 'accreditation',
              case v_standing
                when 'good' then 'Your station is in good standing'
                when 'warning' then 'Action needed: a permit has expired'
                else 'Your accreditation has lapsed'
              end,
              case v_standing
                when 'good' then 'All required permits are current.'
                when 'warning' then 'Upload the renewed permit within ' || v_grace || ' days of its expiry to keep your accreditation.'
                else 'A required permit expired more than ' || v_grace || ' days ago. Your Accredited badge is removed until you upload a valid one.'
              end,
              p_station_id);
    end if;

    if v_standing = 'lapsed' then
      insert into notifications (profile_id, category, title, body, station_id)
      select m.profile_id, 'accreditation', 'Station lapsed: ' || s.station_name,
             'A required permit is past expiry and the grace period.', p_station_id
        from memberships m where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
    end if;
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- The permit trigger now goes through the same function.
create or replace function recompute_accreditation() returns trigger as $$
begin
  perform refresh_station_compliance(new.station_id);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- A new expiry date (a renewal) or a change to which permits are required
-- also re-works the standing at once; the trigger above fires on status
-- only.
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_refresh_compliance_on_permit_dates') then
    create trigger trg_refresh_compliance_on_permit_dates
      after update of expiry_date, is_required on permits
      for each row execute function recompute_accreditation();
  end if;
end $$;

-- Standing and accreditation are WASA's (or the system's) to set. The
-- daily job runs with no signed-in user, which the guard now allows; no
-- client ever reaches water_stations without one.
create or replace function prevent_owner_self_accreditation() returns trigger as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not auth_has_role('wasa_admin') then
    if new.is_accredited is distinct from old.is_accredited
       or new.accreditation_status is distinct from old.accreditation_status
       or new.is_colorum_verified is distinct from old.is_colorum_verified
       or new.is_active is distinct from old.is_active
       or new.standing is distinct from old.standing
       or new.standing_since is distinct from old.standing_since then
      raise exception 'Only WASA admin may change accreditation, standing, verification, or active status.';
    end if;
  elsif (new.is_accredited is distinct from old.is_accredited
         or new.accreditation_override_by is distinct from old.accreditation_override_by
         or new.is_active is distinct from old.is_active)
        and auth_linked_to_station(new.id) then
    raise exception 'You are linked to this station, so another officer must decide its accreditation.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- An officer certifying a station by hand, or closing/reopening it, shows
-- in its standing at once rather than at the next daily run. Fires only on
-- those columns, which refresh_station_compliance never writes, so it
-- can't loop.
create or replace function refresh_compliance_on_station_change() returns trigger as $$
begin
  perform refresh_station_compliance(new.id);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_refresh_compliance_on_station_change') then
    create trigger trg_refresh_compliance_on_station_change
      after update of accreditation_override_by, is_active on water_stations
      for each row execute function refresh_compliance_on_station_change();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Daily job
-- ---------------------------------------------------------------------
create table if not exists compliance_reminders (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('permit', 'credential')),
  ref_id uuid not null,
  expiry_date date not null,
  threshold text not null check (threshold in ('30', '7', 'expired')),
  sent_at timestamptz not null default now(),
  unique (kind, ref_id, expiry_date, threshold)
);
alter table compliance_reminders enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'compliance_reminders' and policyname = 'compliance_reminders_admin_read') then
    create policy compliance_reminders_admin_read on compliance_reminders for select using (auth_has_role('wasa_admin'));
  end if;
end $$;

create or replace function run_daily_compliance() returns void as $$
declare
  r record;
  v_threshold text;
  v_days int;
  v_label text;
begin
  -- Permits.
  for r in
    select p.id, p.station_id, p.permit_type, p.expiry_date, ws.owner_profile_id, ws.station_name
      from permits p join water_stations ws on ws.id = p.station_id
     where p.is_required and p.status = 'approved' and p.expiry_date is not null
       and p.expiry_date <= current_date + 30 and ws.is_active
  loop
    v_days := r.expiry_date - current_date;
    v_threshold := case when v_days < 0 then 'expired' when v_days <= 7 then '7' else '30' end;
    insert into compliance_reminders (kind, ref_id, expiry_date, threshold)
    values ('permit', r.id, r.expiry_date, v_threshold)
    on conflict do nothing;
    if found and r.owner_profile_id is not null then
      select coalesce(label, initcap(replace(r.permit_type::text, '_', ' '))) into v_label
        from permit_type_labels where permit_type = r.permit_type;
      insert into notifications (profile_id, category, title, body, station_id)
      values (r.owner_profile_id, 'permit',
              case v_threshold
                when 'expired' then coalesce(v_label, 'A permit') || ' has expired'
                else coalesce(v_label, 'A permit') || ' expires in ' || v_days || ' day' || case when v_days = 1 then '' else 's' end
              end,
              case v_threshold
                when 'expired' then 'Upload the renewed permit in the Permit vault within ' || compliance_grace_days()
                                    || ' days to keep your accreditation.'
                else 'Upload the renewal in the Permit vault before ' || to_char(r.expiry_date, 'Mon DD, YYYY') || '.'
              end,
              r.station_id);
    end if;
  end loop;

  -- Driver licences (and any credential with an expiry).
  for r in
    select c.id, c.credential_type, c.expiry_date, w.profile_id as driver_profile, w.full_name, ws.owner_profile_id, ws.id as station_id
      from worker_credentials c
      join workers w on w.id = c.worker_id
      left join water_stations ws on ws.id = w.station_id
     where c.status = 'approved' and c.expiry_date is not null and c.expiry_date <= current_date + 30
  loop
    v_days := r.expiry_date - current_date;
    v_threshold := case when v_days < 0 then 'expired' when v_days <= 7 then '7' else '30' end;
    insert into compliance_reminders (kind, ref_id, expiry_date, threshold)
    values ('credential', r.id, r.expiry_date, v_threshold)
    on conflict do nothing;
    if found then
      insert into notifications (profile_id, category, title, body, station_id)
      select p, 'worker',
             case v_threshold
               when 'expired' then initcap(replace(r.credential_type, '_', ' ')) || ' has expired'
               else initcap(replace(r.credential_type, '_', ' ')) || ' expires in ' || v_days || ' day' || case when v_days = 1 then '' else 's' end
             end,
             coalesce(r.full_name, 'A driver') || ' -- upload the renewed one in the Driver Profile.',
             r.station_id
        from (select r.driver_profile as p union select r.owner_profile_id) t
       where p is not null;
    end if;
  end loop;

  -- Every station's standing, the same clock for all.
  for r in select id from water_stations loop
    perform refresh_station_compliance(r.id);
  end loop;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function run_daily_compliance() from public, anon, authenticated;
revoke execute on function refresh_station_compliance(uuid) from public, anon, authenticated;

create extension if not exists pg_cron;

do $$ begin
  if not exists (select 1 from cron.job where jobname = 'gentri-daily-compliance') then
    -- 22:00 UTC is 06:00 in the Philippines.
    perform cron.schedule('gentri-daily-compliance', '0 22 * * *', 'select public.run_daily_compliance()');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Official notices
-- ---------------------------------------------------------------------
create table if not exists notices (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  body text not null check (length(trim(body)) > 0),
  station_id uuid references water_stations(id) on delete cascade,   -- null: every station
  requires_ack boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists notice_receipts (
  notice_id uuid not null references notices(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key (notice_id, profile_id)
);
alter table notices enable row level security;
alter table notice_receipts enable row level security;

create or replace function auth_owned_station_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from water_stations where owner_profile_id = auth.uid() limit 1;
$$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'notices' and policyname = 'notices_admin_all') then
    create policy notices_admin_all on notices for all using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notices' and policyname = 'notices_station_read') then
    create policy notices_station_read on notices for select
      using (auth_owned_station_id() is not null and (station_id is null or station_id = auth_owned_station_id()));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notice_receipts' and policyname = 'notice_receipts_admin_read') then
    create policy notice_receipts_admin_read on notice_receipts for select using (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notice_receipts' and policyname = 'notice_receipts_self_read') then
    create policy notice_receipts_self_read on notice_receipts for select using (profile_id = auth.uid());
  end if;
end $$;

create or replace function send_notice(p_title text, p_body text, p_station_id uuid default null, p_requires_ack boolean default true)
returns uuid as $$
declare
  v_id uuid;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can send official notices.';
  end if;
  insert into notices (title, body, station_id, requires_ack, created_by)
  values (trim(p_title), trim(p_body), p_station_id, p_requires_ack, auth.uid())
  returning id into v_id;

  insert into notifications (profile_id, category, title, body, station_id)
  select ws.owner_profile_id, 'account', 'Official notice from WASA: ' || trim(p_title),
         case when p_requires_ack then 'Please read and acknowledge it in Notices.' else 'Read it in Notices.' end,
         ws.id
    from water_stations ws
   where ws.owner_profile_id is not null and ws.is_active
     and (p_station_id is null or ws.id = p_station_id);
  return v_id;
end;
$$ language plpgsql security definer set search_path = public;

-- Marks a notice read, and acknowledged when [p_acknowledge].
create or replace function mark_notice(p_notice_id uuid, p_acknowledge boolean default false) returns void as $$
begin
  if not exists (select 1 from notices n where n.id = p_notice_id
                  and (n.station_id is null or n.station_id = auth_owned_station_id())
                  and auth_owned_station_id() is not null) then
    raise exception 'Notice not found.';
  end if;
  insert into notice_receipts (notice_id, profile_id, acknowledged_at)
  values (p_notice_id, auth.uid(), case when p_acknowledge then now() end)
  on conflict (notice_id, profile_id) do update
    set acknowledged_at = coalesce(notice_receipts.acknowledged_at, excluded.acknowledged_at);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function send_notice(text, text, uuid, boolean) to authenticated;
grant execute on function mark_notice(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Compliance cases
-- ---------------------------------------------------------------------
create table if not exists compliance_cases (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  kind text not null check (kind in ('permit', 'water_test', 'conduct', 'complaint')),
  summary text not null check (length(trim(summary)) > 0),
  evidence text,
  status text not null default 'open' check (status in ('open', 'warning_issued', 'board_action', 'resolved')),
  decision text,
  opened_by uuid references profiles(id) on delete set null,
  decided_by uuid references profiles(id) on delete set null,
  decided_at timestamptz,
  station_response text,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists compliance_cases_station_idx on compliance_cases (station_id, created_at desc);
alter table compliance_cases enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'compliance_cases' and policyname = 'compliance_cases_admin_all') then
    create policy compliance_cases_admin_all on compliance_cases for all
      using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'compliance_cases' and policyname = 'compliance_cases_owner_read') then
    create policy compliance_cases_owner_read on compliance_cases for select using (station_id = auth_owned_station_id());
  end if;
end $$;

-- Officers deciding a case they're linked to is a conflict, as with permits.
create or replace function guard_compliance_case() returns trigger as $$
begin
  -- Only officers decide cases; the conflict rule is about them. The
  -- station's own written response (respond_to_case) passes through here
  -- too and must not be refused for being "linked" to its own station.
  if auth.uid() is not null and auth_has_role('wasa_admin') and auth_linked_to_station(new.station_id) then
    raise exception 'You are linked to this station, so another officer must handle its case.';
  end if;
  if tg_op = 'INSERT' then
    new.opened_by := coalesce(new.opened_by, auth.uid());
  elsif new.status is distinct from old.status or new.decision is distinct from old.decision then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_compliance_case') then
    create trigger trg_guard_compliance_case before insert or update on compliance_cases
      for each row execute function guard_compliance_case();
  end if;
end $$;

create or replace function notify_compliance_case() returns trigger as $$
declare
  v_owner uuid;
begin
  select owner_profile_id into v_owner from water_stations where id = new.station_id;
  if v_owner is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    insert into notifications (profile_id, category, title, body, station_id)
    values (v_owner, 'accreditation', 'WASA opened a compliance case', new.summary || ' You can respond in writing under Compliance.', new.station_id);
  elsif new.status is distinct from old.status then
    insert into notifications (profile_id, category, title, body, station_id)
    values (v_owner, 'accreditation', 'Compliance case: ' || replace(new.status, '_', ' '),
            coalesce(new.decision, new.summary), new.station_id);
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_notify_compliance_case') then
    create trigger trg_notify_compliance_case after insert or update on compliance_cases
      for each row execute function notify_compliance_case();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_audit_compliance_cases') then
    create trigger trg_audit_compliance_cases after insert or update or delete on compliance_cases
      for each row execute function audit_row_change();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_audit_notices') then
    create trigger trg_audit_notices after insert or delete on notices
      for each row execute function audit_row_change();
  end if;
end $$;

-- The station's side of the record: one written response (editable).
create or replace function respond_to_case(p_case_id uuid, p_response text) returns void as $$
begin
  if p_response is null or length(trim(p_response)) = 0 then
    raise exception 'Write your response first.';
  end if;
  update compliance_cases set station_response = trim(p_response), responded_at = now()
   where id = p_case_id and station_id = auth_owned_station_id() and status <> 'resolved';
  if not found then
    raise exception 'This case is closed or not yours.';
  end if;
  insert into notifications (profile_id, category, title, body, station_id)
  select m.profile_id, 'accreditation', 'Station responded to a compliance case', left(trim(p_response), 140),
         (select station_id from compliance_cases where id = p_case_id)
    from memberships m where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function respond_to_case(uuid, text) to authenticated;

-- Seat every station's standing once.
do $$
declare r record;
begin
  for r in select id from water_stations loop
    perform refresh_station_compliance(r.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- supabase/patch_public_trust.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Customers and the public (UI/Roles plan Phase 4, Rollout plan "Helping
-- customers find safe water"). Run after patch_compliance.sql. Idempotent.
--
--  1. The public station listing carries what lets a customer judge a
--     station at a glance: its standing, the month its last water test was
--     approved, when its sanitary permit is valid until, and how long it has
--     been a member (for the "New member" label).
--  2. Report a problem: a customer can report a station to WASA (taste,
--     smell, cloudy water, dirty jug, late delivery, driver conduct...),
--     optionally about one of their orders and with a photo. Officers see
--     every report; the station sees the reports about it -- without who
--     filed them -- and can respond.
--  3. Customer identity on orders: officers read orders through
--     admin_list_orders(), which leaves out the customer's name and phone
--     unless the order is linked to a report filed with WASA. The direct
--     officer read of the orders table is narrowed to nothing. (Decision,
--     18 Oct 2026: a station's customers belong to that station.)
--  4. Four starter articles on safe water, editable under Website.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Public station facts (columns appended; the view keeps its owner's
--    rights, as before, because it is the public directory)
-- ---------------------------------------------------------------------
create or replace view public_stations as
 select ws.id,
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
    b.name as barangay_name,
    coalesce(r.avg_rating, (0)::numeric) as avg_rating,
    coalesce(r.review_count, (0)::bigint) as review_count,
    ws.standing,
    ws.created_at as member_since,
    ws.accredited_at,
    (select max(p.reviewed_at) from permits p
      where p.station_id = ws.id and p.permit_type = 'water_quality_test_report' and p.status = 'approved') as last_water_test_at,
    (select max(p.expiry_date) from permits p
      where p.station_id = ws.id and p.permit_type = 'sanitary_permit' and p.status = 'approved') as sanitary_valid_until
   from water_stations ws
     left join barangays b on b.id = ws.barangay_id
     left join (select reviews.station_id,
            (avg(reviews.rating))::numeric(3,2) as avg_rating,
            count(*) as review_count
           from reviews
          group by reviews.station_id) r on r.station_id = ws.id
  where ws.is_colorum_verified = true and ws.is_active = true;

-- ---------------------------------------------------------------------
-- 2. Reports to WASA
-- ---------------------------------------------------------------------
create table if not exists station_reports (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  reporter_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  order_id uuid references orders(id) on delete set null,
  category text not null check (category in ('taste_smell', 'cloudy', 'dirty_jug', 'late_delivery', 'driver_conduct', 'wrong_order', 'other')),
  details text not null check (length(trim(details)) > 0),
  photo_path text,
  status text not null default 'new' check (status in ('new', 'reviewing', 'resolved', 'dismissed')),
  officer_note text,
  station_response text,
  responded_at timestamptz,
  resolved_by uuid references profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists station_reports_station_idx on station_reports (station_id, created_at desc);
create index if not exists station_reports_order_idx on station_reports (order_id) where order_id is not null;
alter table station_reports enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'station_reports' and policyname = 'station_reports_customer_insert') then
    create policy station_reports_customer_insert on station_reports for insert
      with check (reporter_id = auth.uid() and auth_has_role('public_consumer'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'station_reports' and policyname = 'station_reports_reporter_read') then
    create policy station_reports_reporter_read on station_reports for select using (reporter_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'station_reports' and policyname = 'station_reports_admin_all') then
    create policy station_reports_admin_all on station_reports for all
      using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
end $$;

create or replace function guard_station_report() returns trigger as $$
begin
  if tg_op = 'INSERT' then
    -- An order named in a report must be the reporter's own, at that station.
    if new.order_id is not null and not exists (
      select 1 from orders where id = new.order_id and customer_profile_id = new.reporter_id and station_id = new.station_id
    ) then
      raise exception 'That order isn''t one of yours from this station.';
    end if;
    new.status := 'new';
  elsif new.status is distinct from old.status and new.status in ('resolved', 'dismissed') then
    new.resolved_by := auth.uid();
    new.resolved_at := now();
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function notify_station_report() returns trigger as $$
declare
  v_owner uuid;
  v_station text;
begin
  select owner_profile_id, station_name into v_owner, v_station from water_stations where id = new.station_id;
  if tg_op = 'INSERT' then
    insert into notifications (profile_id, category, title, body, station_id)
    select m.profile_id, 'accreditation', 'Customer report: ' || v_station, left(new.details, 140), new.station_id
      from memberships m where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, station_id)
      values (v_owner, 'accreditation', 'A customer reported a problem', 'WASA has been told too. Read it and respond under Customer Reviews.', new.station_id);
    end if;
  elsif new.status is distinct from old.status then
    insert into notifications (profile_id, category, title, body, order_id, station_id)
    values (new.reporter_id, case when new.order_id is null then 'account' else 'order' end,
            'Your report about ' || v_station || ': ' || new.status,
            coalesce(new.officer_note, 'WASA updated your report.'), new.order_id, new.station_id);
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_station_report') then
    create trigger trg_guard_station_report before insert or update on station_reports
      for each row execute function guard_station_report();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_notify_station_report') then
    create trigger trg_notify_station_report after insert or update on station_reports
      for each row execute function notify_station_report();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_audit_station_reports') then
    create trigger trg_audit_station_reports after update or delete on station_reports
      for each row execute function audit_row_change();
  end if;
end $$;

-- The station's view of reports about it: what, when and status -- never
-- who filed it.
create or replace function owner_list_reports()
returns table (id uuid, category text, details text, status text, officer_note text, station_response text, created_at timestamptz, about_an_order boolean)
as $$
begin
  return query
    select r.id, r.category, r.details, r.status, r.officer_note, r.station_response, r.created_at, r.order_id is not null
      from station_reports r
     where r.station_id = auth_owned_station_id()
     order by r.created_at desc;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function owner_respond_report(p_report_id uuid, p_response text) returns void as $$
begin
  if p_response is null or length(trim(p_response)) = 0 then
    raise exception 'Write your response first.';
  end if;
  update station_reports set station_response = trim(p_response), responded_at = now()
   where id = p_report_id and station_id = auth_owned_station_id();
  if not found then
    raise exception 'Report not found.';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function owner_list_reports() to authenticated;
grant execute on function owner_respond_report(uuid, text) to authenticated;

-- Photos: private bucket; the reporter uploads under their own folder,
-- officers read.
insert into storage.buckets (id, name, public) values ('station-reports', 'station-reports', false)
on conflict (id) do nothing;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and policyname = 'station_reports_upload') then
    create policy station_reports_upload on storage.objects for insert
      with check (bucket_id = 'station-reports' and (storage.foldername(name))[1]::uuid = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and policyname = 'station_reports_read') then
    create policy station_reports_read on storage.objects for select
      using (bucket_id = 'station-reports' and (auth_has_role('wasa_admin') or (storage.foldername(name))[1]::uuid = auth.uid()));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Officers and customer identity on orders
-- ---------------------------------------------------------------------
create or replace function admin_list_orders(p_limit int default 500)
returns table (
  id uuid, status text, created_at timestamptz, scheduled_for timestamptz,
  jugs_ordered int, water_type text, jug_type text, product_kind text,
  total_amount numeric, payment_method text, payment_collected boolean,
  failure_reason text, failed_at timestamptz,
  station_id uuid, station_name text, driver_name text,
  has_report boolean, customer_name text, customer_phone text
) as $$
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can list orders.';
  end if;
  return query
    select o.id, o.status::text, o.created_at, o.scheduled_for,
           o.jugs_ordered, o.water_type, o.jug_type, o.product_kind,
           o.total_amount, o.payment_method, o.payment_collected,
           o.failure_reason, o.failed_at,
           o.station_id, ws.station_name, w.full_name,
           rep.has_report,
           case when rep.has_report then coalesce(p.full_name, o.guest_name) end,
           case when rep.has_report then coalesce(o.customer_phone, o.guest_phone, p.phone_number) end
      from orders o
      left join water_stations ws on ws.id = o.station_id
      left join workers w on w.id = o.driver_worker_id
      left join profiles p on p.id = o.customer_profile_id
      cross join lateral (select exists (select 1 from station_reports sr where sr.order_id = o.id) as has_report) rep
     order by o.created_at desc
     limit greatest(1, least(p_limit, 2000));
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function admin_list_orders(int) to authenticated;

-- Officers no longer read the orders table directly (the function above is
-- their way in). Narrowed rather than removed so it can be reopened.
alter policy orders_admin_read on orders using (false);

-- ---------------------------------------------------------------------
-- 4. Safe-water articles
-- ---------------------------------------------------------------------
insert into web_content_items (page_key, item_key, icon, title, body, sort_order)
select 'safe_water', 'articles', v.icon, v.title, v.body, v.sort_order
  from (values
    ('science', 'What the monthly water test means',
     'Every member station sends a sample of its water to a laboratory accredited by the Department of Health each month. The lab checks for bacteria such as coliform. A station''s page shows the month its last passed test was approved by WASA -- if it is more than a month or two old, ask the station about it.', 1),
    ('cleaning_services', 'How to tell a jug was cleaned',
     'A sanitised jug has no slime or smell inside, a clean cap, and a seal that is new for every refill. Water should look clear with nothing floating in it. You can ask to see the station''s cleaning routine.', 2),
    ('kitchen', 'Storing refilled water at home',
     'Keep jugs out of direct sunlight, off the floor and away from chemicals or fuel. Use an opened jug within a few days, and wash your dispenser regularly. Return empty jugs dry and capped.', 3),
    ('verified', 'Why the cheapest station isn''t always the safest',
     'Testing, filters, UV lamps and proper cleaning all cost money. Choose a station with a current accreditation and a recent water test -- the price is the station''s own choice, but safety is what the WASA badge vouches for.', 4)
  ) as v(icon, title, body, sort_order)
 where not exists (select 1 from web_content_items where page_key = 'safe_water');

-- =====================================================================
-- patch_stations_members.sql -- Phase 5 (stations, suki, new members)
--
--   1. Phone and walk-in orders, entered by the owner or station staff
--   2. Mentor pairing: officers pair a new station with an experienced one
--   3. A private cost calculator, the owner's alone (no officer policy)
--   4. Jug settlement disputes, flagged by either station, for officers
--   5. "I'll attend" for association events
--
-- Idempotent; no drops, so it can be applied by the connector. Mirrored
-- into reset_and_rebuild.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Phone and walk-in orders
--    orders.order_channel says where an order came from. A walk-in sale is
--    recorded as done and paid at once; a phone order is a normal pending
--    order (delivery to a pin, or pickup at the station). Priced on the
--    server from the station's product, like insert_quick_order.
-- ---------------------------------------------------------------------
alter table orders add column if not exists order_channel text not null default 'app';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'orders_order_channel_check') then
    alter table orders add constraint orders_order_channel_check check (order_channel in ('app', 'phone', 'walk_in'));
  end if;
end $$;

-- The station the caller works for: the one they own, or staff at.
create or replace function auth_station_side_station_id() returns uuid as $$
  select coalesce(auth_owned_station_id(), auth_staff_station_id());
$$ language sql stable security definer set search_path = public;

create or replace function station_create_order(
  p_product_id uuid,
  p_quantity integer,
  p_customer_name text default null,
  p_phone text default null,
  p_channel text default 'phone',
  p_pickup boolean default true,
  p_lat double precision default null,
  p_lng double precision default null,
  p_scheduled_for timestamptz default null
) returns uuid as $$
declare
  v_station uuid := auth_station_side_station_id();
  s water_stations%rowtype;
  p station_products%rowtype;
  v_fee numeric(10,2);
  v_subtotal numeric(10,2);
  v_id uuid;
begin
  if v_station is null then
    raise exception 'Only a station''s owner or staff can enter orders.';
  end if;
  if p_channel not in ('phone', 'walk_in') then
    raise exception 'Choose phone or walk-in.';
  end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 50 then
    raise exception 'Please enter a quantity between 1 and 50.';
  end if;
  select * into s from water_stations where id = v_station;
  select * into p from station_products where id = p_product_id and station_id = v_station;
  if not found then
    raise exception 'That product is not sold by your station.';
  end if;
  if not p.is_available then
    raise exception 'That product is marked unavailable.';
  end if;
  if p_channel = 'phone' and coalesce(trim(p_phone), '') = '' then
    raise exception 'Enter the caller''s phone number.';
  end if;
  if not p_pickup and (p_lat is null or p_lng is null) then
    raise exception 'Pin the delivery address on the map.';
  end if;

  v_fee := case when p_pickup or p_channel = 'walk_in' then 0 else s.delivery_fee end;
  v_subtotal := p_quantity * p.price;

  perform set_config('gentri.trusted_order_change', 'on', true);
  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone, customer_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, scheduled_for,
    product_id, unit_price, product_kind, order_channel,
    status, payment_collected
  ) values (
    v_station, null,
    coalesce(nullif(trim(p_customer_name), ''), case when p_channel = 'walk_in' then 'Walk-in' else 'Phone order' end),
    nullif(trim(p_phone), ''), nullif(trim(p_phone), ''),
    case when p_pickup or p_channel = 'walk_in'
      then st_setsrid(st_makepoint(s.longitude, s.latitude), 4326)::geography
      else st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography end,
    p_quantity, p.water_type, p.container_code,
    v_subtotal, v_fee, v_subtotal + v_fee, p_scheduled_for,
    p.id, p.price, p.kind, p_channel,
    case when p_channel = 'walk_in' then 'done'::order_status else 'pending'::order_status end,
    case when p_channel = 'walk_in' then true else null end
  ) returning id into v_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
  return v_id;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function station_create_order(uuid, integer, text, text, text, boolean, double precision, double precision, timestamptz) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Mentor pairing
-- ---------------------------------------------------------------------
alter table water_stations add column if not exists mentor_station_id uuid references water_stations(id) on delete set null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'water_stations_mentor_not_self') then
    alter table water_stations add constraint water_stations_mentor_not_self check (mentor_station_id is null or mentor_station_id <> id);
  end if;
end $$;

-- Only officers pair stations; an owner can't pick their own mentor.
create or replace function guard_mentor_change() returns trigger as $$
begin
  if new.mentor_station_id is distinct from old.mentor_station_id
     and auth.uid() is not null and not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can pair a station with a mentor.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_mentor_change') then
    create trigger trg_guard_mentor_change before update on water_stations
      for each row execute function guard_mentor_change();
  end if;
end $$;

-- Tells both stations of a new pairing.
create or replace function notify_mentor_pairing() returns trigger as $$
declare
  v_mentor water_stations%rowtype;
begin
  if new.mentor_station_id is not null and new.mentor_station_id is distinct from old.mentor_station_id then
    select * into v_mentor from water_stations where id = new.mentor_station_id;
    if new.owner_profile_id is not null then
      insert into notifications (profile_id, category, title, body, station_id)
      values (new.owner_profile_id, 'account', 'You have a mentor station',
              v_mentor.station_name || ' will help you through your first months. Their contact is on your dashboard.', new.id);
    end if;
    if v_mentor.owner_profile_id is not null then
      insert into notifications (profile_id, category, title, body, station_id)
      values (v_mentor.owner_profile_id, 'account', 'WASA paired you with a new station',
              new.station_name || ' is joining the association. Their contact is on your dashboard.', v_mentor.id);
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_notify_mentor_pairing') then
    create trigger trg_notify_mentor_pairing after update of mentor_station_id on water_stations
      for each row execute function notify_mentor_pairing();
  end if;
end $$;

-- The caller's mentor and mentees, with who to call -- owner names and
-- phones are otherwise private.
create or replace function my_mentor_pairs()
returns table (relation text, station_id uuid, station_name text, owner_name text, owner_phone text, barangay_name text)
as $$
declare
  v_station uuid := auth_owned_station_id();
begin
  if v_station is null then
    return;
  end if;
  return query
    select 'mentor'::text, m.id, m.station_name, pr.full_name, pr.phone_number, b.name
      from water_stations me
      join water_stations m on m.id = me.mentor_station_id
      left join profiles pr on pr.id = m.owner_profile_id
      left join barangays b on b.id = m.barangay_id
     where me.id = v_station
    union all
    select 'mentee'::text, m.id, m.station_name, pr.full_name, pr.phone_number, b.name
      from water_stations m
      left join profiles pr on pr.id = m.owner_profile_id
      left join barangays b on b.id = m.barangay_id
     where m.mentor_station_id = v_station;
end;
$$ language plpgsql stable security definer set search_path = public;

grant execute on function my_mentor_pairs() to authenticated;

-- ---------------------------------------------------------------------
-- 3. Private cost calculator -- the owner's own numbers. No officer
--    policy: the association has no business seeing a member's costs.
-- ---------------------------------------------------------------------
create table if not exists station_cost_profiles (
  station_id uuid primary key references water_stations(id) on delete cascade,
  monthly_rent numeric(12,2) not null default 0,
  monthly_power numeric(12,2) not null default 0,
  monthly_water_source numeric(12,2) not null default 0,
  monthly_filters_maintenance numeric(12,2) not null default 0,
  monthly_wages numeric(12,2) not null default 0,
  monthly_other numeric(12,2) not null default 0,
  cost_per_refill_supplies numeric(12,2) not null default 0,
  refills_per_month integer not null default 0 check (refills_per_month >= 0),
  updated_at timestamptz not null default now()
);
alter table station_cost_profiles enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'station_cost_profiles' and policyname = 'station_cost_profiles_owner_all') then
    create policy station_cost_profiles_owner_all on station_cost_profiles for all
      using (station_id = auth_owned_station_id())
      with check (station_id = auth_owned_station_id());
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Jug settlement disputes
-- ---------------------------------------------------------------------
alter table jug_settlements add column if not exists disputed_at timestamptz;
alter table jug_settlements add column if not exists disputed_by uuid references profiles(id) on delete set null;
alter table jug_settlements add column if not exists dispute_reason text;
alter table jug_settlements add column if not exists dispute_resolved_at timestamptz;
alter table jug_settlements add column if not exists dispute_resolution text;

create or replace function dispute_jug_settlement(p_settlement_id uuid, p_reason text) returns void as $$
declare
  s jug_settlements%rowtype;
  v_station uuid := auth_owned_station_id();
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say what is wrong with this settlement.';
  end if;
  select * into s from jug_settlements where id = p_settlement_id for update;
  if not found then
    raise exception 'Settlement not found.';
  end if;
  if v_station is null or v_station not in (s.holder_station_id, s.owner_station_id) then
    raise exception 'Only the two stations in a settlement can dispute it.';
  end if;
  if s.disputed_at is not null and s.dispute_resolved_at is null then
    raise exception 'This settlement is already disputed and waiting for WASA.';
  end if;
  update jug_settlements
     set disputed_at = now(), disputed_by = auth.uid(), dispute_reason = trim(p_reason),
         dispute_resolved_at = null, dispute_resolution = null
   where id = p_settlement_id;
  insert into notifications (profile_id, category, title, body, station_id)
  select m.profile_id, 'account', 'Jug settlement disputed', left(trim(p_reason), 140), v_station
    from memberships m where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function resolve_jug_dispute(p_settlement_id uuid, p_resolution text) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can resolve a dispute.';
  end if;
  if coalesce(trim(p_resolution), '') = '' then
    raise exception 'Write the decision.';
  end if;
  select * into s from jug_settlements where id = p_settlement_id for update;
  if not found or s.disputed_at is null then
    raise exception 'That settlement is not disputed.';
  end if;
  update jug_settlements set dispute_resolved_at = now(), dispute_resolution = trim(p_resolution)
   where id = p_settlement_id;
  insert into notifications (profile_id, category, title, body, station_id)
  select ws.owner_profile_id, 'account', 'WASA decided a jug settlement dispute', left(trim(p_resolution), 140), ws.id
    from water_stations ws
   where ws.id in (s.holder_station_id, s.owner_station_id) and ws.owner_profile_id is not null;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function dispute_jug_settlement(uuid, text) to authenticated;
grant execute on function resolve_jug_dispute(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Event RSVPs
-- ---------------------------------------------------------------------
create table if not exists event_rsvps (
  event_id uuid not null references events(id) on delete cascade,
  profile_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, profile_id)
);
alter table event_rsvps enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'event_rsvps' and policyname = 'event_rsvps_self_insert') then
    create policy event_rsvps_self_insert on event_rsvps for insert with check (profile_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'event_rsvps' and policyname = 'event_rsvps_self_delete') then
    create policy event_rsvps_self_delete on event_rsvps for delete using (profile_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'event_rsvps' and policyname = 'event_rsvps_self_or_admin_read') then
    create policy event_rsvps_self_or_admin_read on event_rsvps for select
      using (profile_id = auth.uid() or auth_has_role('wasa_admin'));
  end if;
end $$;

-- Head counts are public; who is going is not.
create or replace function event_rsvp_counts() returns table (event_id uuid, going integer) as $$
  select r.event_id, count(*)::int from event_rsvps r group by r.event_id;
$$ language sql stable security definer set search_path = public;

grant execute on function event_rsvp_counts() to anon, authenticated;

-- =====================================================================
-- patch_help_settings.sql -- Phase 6 (help, settings, order steps)
--
--   1. Order step times: when an order was assigned, went out, was
--      delivered or cancelled -- set by the database on each status change,
--      so no app can write or alter them.
--   2. Notification preferences: mute a category. Enforced where
--      notifications are created, so every source respects it. Account and
--      accreditation notices (official, security) can't be muted.
--
-- Idempotent; no drops. Mirrored into reset_and_rebuild.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Order step times
-- ---------------------------------------------------------------------
alter table orders add column if not exists assigned_at timestamptz;
alter table orders add column if not exists out_for_delivery_at timestamptz;
alter table orders add column if not exists delivered_at timestamptz;
alter table orders add column if not exists cancelled_at timestamptz;

create or replace function set_order_step_times() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    -- Never edited directly: carried over unless the status moves.
    new.assigned_at := old.assigned_at;
    new.out_for_delivery_at := old.out_for_delivery_at;
    new.delivered_at := old.delivered_at;
    new.cancelled_at := old.cancelled_at;
    if new.status is not distinct from old.status then
      return new;
    end if;
  else
    new.assigned_at := null;
    new.out_for_delivery_at := null;
    new.delivered_at := null;
    new.cancelled_at := null;
  end if;

  case new.status
    when 'assigned' then new.assigned_at := now();
    when 'active' then
      new.out_for_delivery_at := now();
      new.assigned_at := coalesce(new.assigned_at, now());
    when 'done' then new.delivered_at := now();
    when 'cancelled' then new.cancelled_at := now();
    when 'pending' then
      -- Unassigned (or a failed delivery put back): the earlier steps no
      -- longer hold.
      new.assigned_at := null;
      new.out_for_delivery_at := null;
    else null;
  end case;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_set_order_step_times') then
    create trigger trg_set_order_step_times before insert or update on orders
      for each row execute function set_order_step_times();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Notification preferences
-- ---------------------------------------------------------------------
create table if not exists notification_preferences (
  profile_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  category text not null check (category in ('order', 'permit', 'worker', 'bulletin')),
  muted boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (profile_id, category)
);
alter table notification_preferences enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'notification_preferences' and policyname = 'notification_preferences_self_all') then
    create policy notification_preferences_self_all on notification_preferences for all
      using (profile_id = auth.uid())
      with check (profile_id = auth.uid());
  end if;
end $$;

-- Drops a notification its recipient muted. Returning null from a BEFORE
-- INSERT trigger skips the row and nothing else.
create or replace function respect_notification_preferences() returns trigger as $$
begin
  if exists (
    select 1 from notification_preferences p
     where p.profile_id = new.profile_id and p.category = new.category and p.muted
  ) then
    return null;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_respect_notification_preferences') then
    create trigger trg_respect_notification_preferences before insert on notifications
      for each row execute function respect_notification_preferences();
  end if;
end $$;

-- =====================================================================
-- patch_trash.sql -- Trash, and officers' view of orders
--
--   1. Officers see an order only when a customer filed a report about it
--      (decision of 18 Oct 2026: no list of other stations' orders).
--   2. Trash: anything deleted in the app or portals is kept for 5 days and
--      can be restored by whoever deleted it, or by an officer. After 5
--      days a daily job removes it for good. Cascaded rows (a post's
--      comments and reactions, an event's RSVPs) go with their parent and
--      come back with it.
--
-- Run after patch_help_settings.sql. Idempotent; no drops.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Reported orders only
-- ---------------------------------------------------------------------
create or replace function admin_list_orders(p_limit int default 500)
returns table (
  id uuid, status text, created_at timestamptz, scheduled_for timestamptz,
  jugs_ordered int, water_type text, jug_type text, product_kind text,
  total_amount numeric, payment_method text, payment_collected boolean,
  failure_reason text, failed_at timestamptz,
  station_id uuid, station_name text, driver_name text,
  has_report boolean, customer_name text, customer_phone text
) as $$
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can list orders.';
  end if;
  return query
    select o.id, o.status::text, o.created_at, o.scheduled_for,
           o.jugs_ordered, o.water_type, o.jug_type, o.product_kind,
           o.total_amount, o.payment_method, o.payment_collected,
           o.failure_reason, o.failed_at,
           o.station_id, ws.station_name, w.full_name,
           true,
           coalesce(p.full_name, o.guest_name),
           coalesce(o.customer_phone, o.guest_phone, p.phone_number)
      from orders o
      left join water_stations ws on ws.id = o.station_id
      left join workers w on w.id = o.driver_worker_id
      left join profiles p on p.id = o.customer_profile_id
     where exists (select 1 from station_reports sr where sr.order_id = o.id)
     order by o.created_at desc
     limit greatest(1, least(p_limit, 2000));
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 2. Trash
-- ---------------------------------------------------------------------
create table if not exists trash (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null,
  is_child boolean not null default false,
  table_name text not null,
  row_data jsonb not null,
  kind text not null,
  label text,
  station_id uuid,
  deleted_by uuid references profiles(id) on delete set null,
  deleted_at timestamptz not null default now(),
  purge_after timestamptz not null default now() + interval '5 days'
);
create index if not exists trash_batch_idx on trash (batch_id);
create index if not exists trash_purge_idx on trash (purge_after);
alter table trash enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'trash' and policyname = 'trash_owner_or_officer_read') then
    create policy trash_owner_or_officer_read on trash for select
      using (deleted_by = auth.uid() or auth_has_role('wasa_admin'));
  end if;
end $$;

-- Files of purged items (a resource's PDF) wait here until an officer's
-- portal removes them from storage -- SQL can't delete storage files.
create table if not exists storage_cleanup (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  path text not null,
  queued_at timestamptz not null default now()
);
alter table storage_cleanup enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'storage_cleanup' and policyname = 'storage_cleanup_officer_all') then
    create policy storage_cleanup_officer_all on storage_cleanup for all
      using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
end $$;

-- What each table's rows are called in the Trash.
create or replace function trash_kind(p_table text) returns text as $$
  select case p_table
    when 'bulletins' then 'Board post'
    when 'bulletin_comments' then 'Comment'
    when 'bulletin_reactions' then 'Reaction'
    when 'bulletin_reports' then 'Post report'
    when 'customer_addresses' then 'Saved address'
    when 'events' then 'Event'
    when 'event_rsvps' then 'RSVP'
    when 'floor_prices' then 'Floor price'
    when 'resources' then 'Resource'
    when 'reviews' then 'Review'
    when 'station_products' then 'Product'
    when 'web_content_items' then 'Website item'
    when 'web_faq_entries' then 'FAQ entry'
    else p_table end;
$$ language sql immutable;

-- BEFORE DELETE on every deletable table. A delete the user made starts a
-- batch; rows removed by cascade from it join that batch as children.
-- With the argument 'children', a table is only caught by cascade (a
-- reaction someone takes back isn't "deleted").
create or replace function move_to_trash() returns trigger as $$
declare
  r jsonb := to_jsonb(old);
  v_batch uuid;
  v_child boolean := pg_trigger_depth() > 1;
begin
  -- No signed-in user: the server itself is deleting -- account deletion
  -- (whose cascades must not keep a deleted person's data for 5 days) or a
  -- scheduled job. Gone for good, as before.
  if auth.uid() is null or coalesce(current_setting('gentri.no_trash', true), '') = 'on' then
    return old;
  end if;
  if tg_nargs > 0 and tg_argv[0] = 'children' and not v_child then
    return old;
  end if;
  v_batch := nullif(current_setting('gentri.trash_batch', true), '')::uuid;
  if not v_child or v_batch is null then
    v_batch := gen_random_uuid();
    v_child := false;
    perform set_config('gentri.trash_batch', v_batch::text, true);
  end if;
  insert into trash (batch_id, is_child, table_name, row_data, kind, label, station_id, deleted_by)
  values (
    v_batch, v_child, tg_table_name, r, trash_kind(tg_table_name),
    left(coalesce(r->>'title', r->>'question', r->>'label', r->>'name',
                  r->>'body', r->>'comment', r->>'content', r->>'address_text', r->>'water_type'), 120),
    nullif(r->>'station_id', '')::uuid,
    auth.uid()
  );
  return old;
end;
$$ language plpgsql security definer set search_path = public;

do $$
declare
  t text;
begin
  foreach t in array array['bulletins', 'bulletin_comments', 'customer_addresses', 'events', 'floor_prices',
                           'resources', 'reviews', 'station_products', 'web_content_items', 'web_faq_entries'] loop
    if not exists (select 1 from pg_trigger where tgname = 'trg_trash_' || t) then
      execute format('create trigger %I before delete on %I for each row execute function move_to_trash()', 'trg_trash_' || t, t);
    end if;
  end loop;
  foreach t in array array['bulletin_reactions', 'bulletin_reports', 'event_rsvps'] loop
    if not exists (select 1 from pg_trigger where tgname = 'trg_trash_' || t) then
      execute format('create trigger %I before delete on %I for each row execute function move_to_trash(''children'')', 'trg_trash_' || t, t);
    end if;
  end loop;
end $$;

-- A restored post keeps its original author, whoever restores it.
create or replace function validate_bulletin_author() returns trigger as $$
begin
  if coalesce(current_setting('gentri.restoring', true), '') = 'on' then
    return new;
  end if;
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
$$ language plpgsql security definer set search_path = public;

create or replace function restore_from_trash(p_trash_id uuid) returns void as $$
declare
  v trash%rowtype;
  item trash%rowtype;
begin
  select * into v from trash where id = p_trash_id and not is_child;
  if not found then
    raise exception 'That item is no longer in the Trash.';
  end if;
  if v.deleted_by is distinct from auth.uid() and not auth_has_role('wasa_admin') then
    raise exception 'Only whoever deleted it, or a WASA officer, can restore this.';
  end if;
  perform set_config('gentri.restoring', 'on', true);
  for item in select * from trash where batch_id = v.batch_id order by is_child, deleted_at loop
    begin
      execute format('insert into %I select * from jsonb_populate_record(null::%I, $1)', item.table_name, item.table_name)
        using item.row_data;
    exception
      when unique_violation then
        if not item.is_child then
          raise exception 'Can''t restore: something with the same details already exists.';
        end if;
      when foreign_key_violation then
        if not item.is_child then
          raise exception 'Can''t restore: what it belonged to has been removed for good.';
        end if;
    end;
  end loop;
  perform set_config('gentri.restoring', 'off', true);
  delete from trash where batch_id = v.batch_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function purge_trash_item(p_trash_id uuid) returns void as $$
declare
  v trash%rowtype;
begin
  select * into v from trash where id = p_trash_id and not is_child;
  if not found then
    raise exception 'That item is no longer in the Trash.';
  end if;
  if v.deleted_by is distinct from auth.uid() and not auth_has_role('wasa_admin') then
    raise exception 'Only whoever deleted it, or a WASA officer, can delete this for good.';
  end if;
  insert into storage_cleanup (bucket, path)
  select 'resources', t.row_data->>'storage_path' from trash t
   where t.batch_id = v.batch_id and t.table_name = 'resources' and coalesce(t.row_data->>'storage_path', '') <> '';
  delete from trash where batch_id = v.batch_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function purge_expired_trash() returns integer as $$
declare
  v_batches uuid[];
begin
  select array_agg(distinct batch_id) into v_batches from trash where not is_child and purge_after < now();
  if v_batches is null then
    return 0;
  end if;
  insert into storage_cleanup (bucket, path)
  select 'resources', t.row_data->>'storage_path' from trash t
   where t.batch_id = any(v_batches) and t.table_name = 'resources' and coalesce(t.row_data->>'storage_path', '') <> '';
  delete from trash where batch_id = any(v_batches);
  return coalesce(array_length(v_batches, 1), 0);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function restore_from_trash(uuid) to authenticated;
grant execute on function purge_trash_item(uuid) to authenticated;

-- Daily, 06:30 Philippine time (22:30 UTC).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (select 1 from cron.job where jobname = 'gentri-purge-trash') then
    perform cron.schedule('gentri-purge-trash', '30 22 * * *', 'select purge_expired_trash()');
  end if;
end $$;

-- =====================================================================
-- patch_test_pass_fixes.sql -- bugs found running the test cases against
-- the live database (18 Oct 2026). Idempotent; no drops.
-- =====================================================================

-- GTW-APP-259: a driver leaving a station while holding a delivery failed
-- outright -- releasing the order back to the station tripped
-- protect_order_financial_fields, which only lets owners and officers
-- change an order's driver. The release is checked here, so it is marked as
-- a trusted change (as driver_switch_station already does).
create or replace function driver_leave_station() returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare v_worker_id uuid;
begin
  select id into v_worker_id from workers where profile_id = auth.uid();

  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;

  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');
  perform set_config('gentri.trusted_order_change', 'off', true);

  update workers set station_id = null, updated_at = now() where id = v_worker_id;
  update memberships set station_id = null where profile_id = auth.uid() and role = 'driver';
  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
end;
$function$;

-- GTW-APP-196 / WEB-254: only cleared drivers take deliveries. Pending
-- drivers (new, or back to pending after an incident) were assignable --
-- only flagged ones were refused.
create or replace function public.set_order_status(p_order_id uuid, p_new_status order_status, p_driver_worker_id uuid default null::uuid, p_guest_phone text default null::text, p_empty_jugs_returned integer default null::integer, p_payment_collected boolean default null::boolean, p_jug_exchange_origin_station_id uuid default null::uuid, p_no_jug_exchange boolean default false)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  o orders%rowtype;
  v_caller_worker_id uuid;
  v_is_station_side boolean;
  v_new_driver_station_id uuid;
  v_new_driver_clearance clearance_status;
begin
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  v_is_station_side := auth_has_role('wasa_admin')
    or exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid())
    or (auth_staff_station_id() is not null and auth_staff_station_id() = o.station_id);

  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  if v_is_station_side then
    perform set_config('gentri.trusted_order_change', 'on', true);
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
      if v_new_driver_clearance is distinct from 'cleared' then
        raise exception 'This driver is not cleared by WASA yet and cannot be assigned deliveries.';
      end if;
      update orders set status = 'assigned', driver_worker_id = p_driver_worker_id where id = p_order_id;
    elsif o.status in ('pending', 'assigned') and p_new_status = 'cancelled' then
      update orders set status = 'cancelled' where id = p_order_id;
    elsif o.status = 'assigned' and p_new_status = 'pending' then
      update orders set status = 'pending', driver_worker_id = null where id = p_order_id;
    else
      perform set_config('gentri.trusted_order_change', 'off', true);
      raise exception 'Not a valid status change for the station.';
    end if;
    perform set_config('gentri.trusted_order_change', 'off', true);
    return;
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
$function$;

-- GTW-WEB-225: a permit or worker credential could be rejected with no
-- reason (the dialog accepted a blank one and so did the table), leaving
-- the owner or driver nothing to fix.
create or replace function require_rejection_reason() returns trigger as $$
begin
  if new.status = 'rejected' and new.status is distinct from old.status
     and coalesce(trim(new.rejection_reason), '') = '' then
    raise exception 'Give a reason for the rejection -- it is sent to them so they know what to fix.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_permits_require_reason') then
    create trigger trg_permits_require_reason before update on permits
      for each row execute function require_rejection_reason();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_credentials_require_reason') then
    create trigger trg_credentials_require_reason before update on worker_credentials
      for each row execute function require_rejection_reason();
  end if;
end $$;

-- GTW-WEB-179: the form requires an incident description, but the table
-- accepted a blank one -- and an incident puts a driver back to pending.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'worker_incidents_description_present') then
    alter table worker_incidents add constraint worker_incidents_description_present
      check (length(trim(description)) > 0) not valid;
  end if;
end $$;

-- GTW-WEB-205 (and spoofing): a post's author name and station name were
-- taken from the app as sent, so a modified app could post as "WASA" or as
-- another station; and a member could pin their own post. The database now
-- fills both names from the account itself and only officers may pin.
create or replace function validate_bulletin_author() returns trigger as $$
begin
  if coalesce(current_setting('gentri.restoring', true), '') = 'on' then
    return new;
  end if;
  if new.posted_by is distinct from auth.uid() then
    raise exception 'posted_by must match the authenticated user.';
  end if;

  if not exists (
    select 1 from memberships
    where profile_id = auth.uid() and role = new.author_role and status = 'active'
  ) then
    raise exception 'author_role does not match an active membership for this account.';
  end if;

  select coalesce(nullif(trim(full_name), ''), 'Member') into new.author_name
    from profiles where id = auth.uid();
  new.author_name := coalesce(new.author_name, 'Member');
  if auth_has_role('wasa_admin') then
    new.author_station_name := null;
  else
    new.is_pinned := false;
    select ws.station_name into new.author_station_name
      from memberships m join water_stations ws on ws.id = m.station_id
     where m.profile_id = auth.uid() and m.role = new.author_role and m.status = 'active'
     limit 1;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- GTW-WEB-260 / APP-027: the forms refuse a blank post title or comment;
-- the tables now do too.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bulletins_title_present') then
    alter table bulletins add constraint bulletins_title_present check (length(trim(title)) > 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bulletin_comments_body_present') then
    alter table bulletin_comments add constraint bulletin_comments_body_present check (length(trim(body)) > 0) not valid;
  end if;
end $$;

-- GTW-WEB-161 / 163: a settlement for more jugs than are outstanding (or
-- for none) was accepted when proposed and only refused when the other
-- station tried to confirm it. Refused when proposed now, with the balance.
create or replace function check_jug_settlement_proposal() returns trigger as $$
declare
  v_owed int;
begin
  if new.quantity is null or new.quantity < 1 then
    raise exception 'Enter how many jugs you are returning.';
  end if;
  select coalesce(sum(quantity), 0) into v_owed
    from jug_ledger_entries
   where holder_station_id = new.holder_station_id
     and owner_station_id = new.owner_station_id
     and jug_type = new.jug_type;
  if new.quantity > v_owed then
    raise exception 'You hold % of their jugs of this type, so you can settle at most that many.', v_owed;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_check_jug_settlement_proposal') then
    create trigger trg_check_jug_settlement_proposal before insert on jug_settlements
      for each row execute function check_jug_settlement_proposal();
  end if;
end $$;

-- Clearinghouse integrity: either station in a pair could insert any
-- ledger entry -- a negative one erases its own debt, and recorded_by and
-- related_order_id could name anyone. A station may now only record a
-- positive transfer, as itself, not tied to an order. Balances go down only
-- through a confirmed settlement (confirm_jug_settlement) or an officer;
-- order-linked entries come from set_order_status.
alter policy jug_ledger_involved_insert on jug_ledger_entries
  with check (
    ((holder_station_id in (select id from water_stations where owner_profile_id = auth.uid()))
      or (owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())))
    and quantity > 0
    and recorded_by = auth.uid()
    and related_order_id is null
  );

-- ---------------------------------------------------------------------
-- Direct-write guards (security sweep). The app changes orders, drivers,
-- permits and stations through checked functions (set_order_status,
-- insert_quick_order, station_create_order, driver_switch_station, ...).
-- The table policies were wider than that, so a modified app could:
--   * create orders in any customer's name for its station,
--   * clear its own flagged driver, or add a "cleared" driver,
--   * delete its permits so its station counted as fully accredited,
--   * change an order's status directly as its driver.
-- A write straight from a signed-in user (current_user 'authenticated',
-- not inside a function or another trigger) now may only touch what the
-- screens actually edit. Officers keep full access.
-- ---------------------------------------------------------------------
create or replace function is_direct_member_write() returns boolean as $$
  select current_user in ('authenticated', 'anon')
     and pg_trigger_depth() <= 1
     and not auth_has_role('wasa_admin');
$$ language sql stable set search_path = public;  -- invoker: must see the caller's role

create or replace function guard_direct_order_write() returns trigger as $$
begin
  if is_direct_member_write() then
    raise exception 'Orders can only be placed and changed through the order screens.';
  end if;
  return coalesce(new, old);
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_worker_write() returns trigger as $$
begin
  if not is_direct_member_write() then
    return coalesce(new, old);
  end if;
  if tg_op <> 'UPDATE' then
    raise exception 'Drivers join and leave a station with an invite code, not directly.';
  end if;
  -- Name, phone, plate and capacity only; clearance is WASA's, the station
  -- changes through join/leave.
  if (to_jsonb(new) - array['full_name', 'phone_number', 'vehicle_plate', 'jug_capacity', 'role_title', 'updated_at'])
     is distinct from (to_jsonb(old) - array['full_name', 'phone_number', 'vehicle_plate', 'jug_capacity', 'role_title', 'updated_at']) then
    raise exception 'Only WASA can change a driver''s clearance or station.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_permit_write() returns trigger as $$
begin
  if not is_direct_member_write() then
    return coalesce(new, old);
  end if;
  if tg_op <> 'UPDATE' then
    raise exception 'Permits are set by the association; upload a document to the one listed.';
  end if;
  -- An upload: the file, when, and back to review.
  if (to_jsonb(new) - array['storage_path', 'uploaded_at', 'status'])
     is distinct from (to_jsonb(old) - array['storage_path', 'uploaded_at', 'status'])
     or (new.status is distinct from old.status and new.status <> 'pending_review') then
    raise exception 'Only WASA can change which permits are required or decide them.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_station_delete() returns trigger as $$
begin
  if is_direct_member_write() then
    raise exception 'A station is closed by WASA, not deleted.';
  end if;
  return old;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_order_write') then
    create trigger trg_guard_direct_order_write before insert or update or delete on orders
      for each row execute function guard_direct_order_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_worker_write') then
    create trigger trg_guard_direct_worker_write before insert or update or delete on workers
      for each row execute function guard_direct_worker_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_permit_write') then
    create trigger trg_guard_direct_permit_write before insert or update or delete on permits
      for each row execute function guard_direct_permit_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_station_delete') then
    create trigger trg_guard_direct_station_delete before delete on water_stations
      for each row execute function guard_direct_station_delete();
  end if;
end $$;

-- A driver's "Save profile" (name, phone, plate, capacity) silently saved
-- nothing: there was no policy letting drivers update their own record.
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'workers' and policyname = 'workers_self_update') then
    create policy workers_self_update on workers for update
      using (profile_id = auth.uid()) with check (profile_id = auth.uid());
  end if;
end $$;

-- Trash: a deleted product was listed as just its water type ("mineral").
-- It now reads like the product list ("Mineral, Round 5-gal").
create or replace function move_to_trash() returns trigger as $$
declare
  r jsonb := to_jsonb(old);
  v_batch uuid;
  v_child boolean := pg_trigger_depth() > 1;
  v_label text;
begin
  if auth.uid() is null or coalesce(current_setting('gentri.no_trash', true), '') = 'on' then
    return old;
  end if;
  if tg_nargs > 0 and tg_argv[0] = 'children' and not v_child then
    return old;
  end if;
  v_batch := nullif(current_setting('gentri.trash_batch', true), '')::uuid;
  if not v_child or v_batch is null then
    v_batch := gen_random_uuid();
    v_child := false;
    perform set_config('gentri.trash_batch', v_batch::text, true);
  end if;
  if tg_table_name = 'station_products' then
    select initcap(r->>'water_type') || ', ' || coalesce(ct.label, r->>'container_code')
           || case when r->>'kind' = 'new_container' then ' (new container)' else '' end
      into v_label
      from (select 1) x left join container_types ct on ct.code = r->>'container_code';
  else
    v_label := coalesce(r->>'title', r->>'question', r->>'label', r->>'name',
                        r->>'body', r->>'comment', r->>'content', r->>'water_type');
  end if;
  insert into trash (batch_id, is_child, table_name, row_data, kind, label, station_id, deleted_by)
  values (v_batch, v_child, tg_table_name, r, trash_kind(tg_table_name), left(v_label, 120),
          nullif(r->>'station_id', '')::uuid, auth.uid());
  return old;
end;
$$ language plpgsql security definer set search_path = public;

-- Security advisor: fixed search_path on the Trash label helper.
alter function trash_kind(text) set search_path = public;

-- =====================================================================
-- patch_cancel_seal_netting.sql -- 19 Oct 2026
--
--   1. Cancelling an order needs a reason, from the customer or the
--      station, and only while it is pending or assigned: once the driver
--      has set out ("out for delivery") nobody can cancel it. Everyone
--      affected is told the reason.
--   2. A station that becomes accredited gets the verification seal at the
--      same time, so it shows in the public directory without a second step.
--   3. Jug balances are netted per pair of stations: 14 jugs one way and 9
--      the other read as one balance of 5. Settlements are checked against
--      the net figure.
--
-- Idempotent; no drops. Mirrored into reset_and_rebuild.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cancel with a reason
-- ---------------------------------------------------------------------
alter table orders add column if not exists cancel_reason text;
alter table orders add column if not exists cancelled_by text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'orders_cancelled_by_check') then
    alter table orders add constraint orders_cancelled_by_check
      check (cancelled_by is null or cancelled_by in ('customer', 'station', 'wasa'));
  end if;
end $$;

create or replace function cancel_order(p_order_id uuid, p_reason text) returns void as $$
declare
  o orders%rowtype;
  v_by text;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why the order is being cancelled.';
  end if;
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  if auth.uid() is not null and o.customer_profile_id = auth.uid() then
    v_by := 'customer';
  elsif exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid())
     or (auth_staff_station_id() is not null and auth_staff_station_id() = o.station_id) then
    v_by := 'station';
  elsif auth_has_role('wasa_admin') then
    v_by := 'wasa';
  else
    raise exception 'Not authorized to cancel this order.';
  end if;

  if o.status = 'active' then
    raise exception 'The driver has already left with this order, so it can no longer be cancelled.';
  elsif o.status not in ('pending', 'assigned') then
    raise exception 'This order is already %, so it can''t be cancelled.',
      case o.status when 'done' then 'delivered' else o.status::text end;
  end if;

  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'cancelled', cancel_reason = left(trim(p_reason), 300), cancelled_by = v_by
   where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function cancel_order(uuid, text) to authenticated;

-- Notifications now carry the cancel reason, and a driver whose delivery
-- is cancelled is told too.
create or replace function notify_order_event() returns trigger
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_owner uuid;
  v_station_name text;
  v_driver_profile uuid;
  v_line text;
  v_failed boolean;
  v_reason text;
begin
  select owner_profile_id, station_name into v_owner, v_station_name
    from water_stations where id = new.station_id;
  v_line := order_line_text(new.jugs_ordered, new.water_type, new.jug_type, new.product_kind);

  if tg_op = 'INSERT' then
    insert into notifications (profile_id, category, title, body, order_id, station_id)
    select p, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id
      from (select v_owner as p
            union
            select m.profile_id from memberships m
             where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
     where p is not null;
    return new;
  end if;

  v_failed := new.failed_at is not null and new.failed_at is distinct from old.failed_at;
  v_reason := case when new.cancel_reason is not null then ' · Reason: ' || new.cancel_reason else '' end;

  if v_failed then
    if new.customer_profile_id is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (new.customer_profile_id, 'order', 'Delivery attempt unsuccessful',
              coalesce(v_station_name, 'Your station') || ' · ' || new.failure_reason
                || '. The station will contact you or try again.',
              new.id, new.station_id);
    end if;
    insert into notifications (profile_id, category, title, body, order_id, station_id)
    select p, 'order', 'Delivery failed: reassign or cancel', v_line || ' · ' || new.failure_reason, new.id, new.station_id
      from (select v_owner as p
            union
            select m.profile_id from memberships m
             where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
     where p is not null;
  elsif new.status is distinct from old.status then
    if new.customer_profile_id is not null and not (new.status = 'cancelled' and new.cancelled_by = 'customer') then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (
        new.customer_profile_id, 'order',
        case new.status
          when 'assigned' then 'A driver is on the way'
          when 'active' then 'Your order is out for delivery'
          when 'done' then 'Order delivered'
          when 'cancelled' then case new.cancelled_by
                                  when 'station' then 'Order cancelled by the station'
                                  when 'wasa' then 'Order cancelled by WASA'
                                  else 'Order cancelled' end
          else 'Order updated'
        end,
        coalesce(v_station_name, 'Your station') || ' · ' || v_line
          || case when new.status = 'cancelled' then v_reason else '' end,
        new.id, new.station_id);
    end if;

    if new.status = 'cancelled' then
      -- The station hears about a cancellation it didn't make itself.
      if new.cancelled_by is distinct from 'station' then
        insert into notifications (profile_id, category, title, body, order_id, station_id)
        select p, 'order',
               case new.cancelled_by
                 when 'wasa' then 'Order cancelled by WASA'
                 when 'customer' then 'Order cancelled by the customer'
                 else 'Order cancelled' end,
               v_line || ' · ' || peso_text(new.total_amount) || v_reason, new.id, new.station_id
          from (select v_owner as p
                union
                select m.profile_id from memberships m
                 where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
         where p is not null;
      end if;
      -- A driver who was holding it no longer needs to go.
      if old.driver_worker_id is not null then
        select profile_id into v_driver_profile from workers where id = old.driver_worker_id;
        if v_driver_profile is not null then
          insert into notifications (profile_id, category, title, body, order_id, station_id)
          values (v_driver_profile, 'order', 'Delivery cancelled', v_line || v_reason, new.id, new.station_id);
        end if;
      end if;
    end if;
  end if;

  if new.driver_worker_id is not null and new.driver_worker_id is distinct from old.driver_worker_id then
    select profile_id into v_driver_profile from workers where id = new.driver_worker_id;
    if v_driver_profile is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_driver_profile, 'order', 'Delivery assigned', v_line, new.id, new.station_id);
    end if;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. Accreditation brings the seal
-- ---------------------------------------------------------------------
create or replace function seal_on_accreditation() returns trigger as $$
begin
  if new.is_accredited and not coalesce(old.is_accredited, false) then
    new.is_colorum_verified := true;
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_a_seal_on_accreditation') then
    -- Named to run before the officer-only guard on the same table.
    create trigger trg_a_seal_on_accreditation before update of is_accredited on water_stations
      for each row execute function seal_on_accreditation();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Netted jug balances
-- ---------------------------------------------------------------------
-- security_invoker: each station still sees only balances it is part of
-- (jug_ledger_entries' own read rules apply).
create or replace view jug_balances with (security_invoker = true) as
  select case when net > 0 then s1 else s2 end as holder_station_id,
         case when net > 0 then s2 else s1 end as owner_station_id,
         jug_type,
         abs(net) as net_qty
    from (
      select least(holder_station_id, owner_station_id) as s1,
             greatest(holder_station_id, owner_station_id) as s2,
             jug_type,
             sum(case when holder_station_id < owner_station_id then quantity else -quantity end) as net
        from jug_ledger_entries
       group by 1, 2, 3
    ) t
   where net <> 0;

-- How many of p_owner's jugs p_holder holds, net of jugs going the other way.
create or replace function jug_net_owed(p_holder uuid, p_owner uuid, p_type jug_type) returns int as $$
  select coalesce(sum(case when holder_station_id = p_holder then quantity else -quantity end), 0)::int
    from jug_ledger_entries
   where jug_type = p_type
     and ((holder_station_id = p_holder and owner_station_id = p_owner)
       or (holder_station_id = p_owner and owner_station_id = p_holder));
$$ language sql stable security definer set search_path = public;

create or replace function check_jug_settlement_proposal() returns trigger as $$
declare
  v_owed int;
begin
  if new.quantity is null or new.quantity < 1 then
    raise exception 'Enter how many jugs you are returning.';
  end if;
  v_owed := jug_net_owed(new.holder_station_id, new.owner_station_id, new.jug_type);
  if new.quantity > v_owed then
    raise exception 'You hold % of their jugs of this type (after netting), so you can settle at most that many.', greatest(v_owed, 0);
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function confirm_jug_settlement(p_settlement_id uuid) returns void
language plpgsql security definer set search_path to 'public'
as $function$
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

  v_owed := jug_net_owed(s.holder_station_id, s.owner_station_id, s.jug_type);

  if s.quantity > v_owed then
    raise exception 'This settlement (% jugs) exceeds the current outstanding balance (% jugs).', s.quantity, greatest(v_owed, 0);
  end if;

  insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by)
    values (s.holder_station_id, s.owner_station_id, s.jug_type, -s.quantity, auth.uid());

  update jug_settlements
    set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    where id = p_settlement_id;
end;
$function$;
