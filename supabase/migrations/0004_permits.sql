-- Permit Vault: business/sanitary/FDA permits plus conditionally-required
-- alkaline documents. Selecting 'alkaline' in water_stations.offered_water_types
-- automatically requires alkaline_tech_cert + alkaline_water_test uploads.
-- is_accredited only flips true once every required permit is approved.

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
  -- Optional -- not every permit type has a hard renewal date, so an admin
  -- may leave this null when approving. When set, permit_review_screen.dart
  -- surfaces a "Renewal due" badge within 30 days of this date.
  expiry_date date,
  uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (station_id, permit_type)
);

create index permits_station_idx on permits (station_id);
create index permits_status_idx on permits (status);

-- Whenever a station is created/updated, make sure the baseline permits
-- exist, and toggle the two alkaline-specific permits' is_required flag
-- based on whether 'alkaline' is in offered_water_types.
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

-- Recompute a station's accreditation whenever a permit's status changes:
-- accredited only when every *required* permit is 'approved'. If a
-- previously-approved permit later gets rejected (all_ok flips to false),
-- downgrade accreditation_status to 'under_review' rather than leaving it
-- stuck at the stale 'accredited' text forever -- but only when it was
-- 'accredited' to begin with, so an admin-set 'rejected'/'suspended'
-- status is never silently overwritten by this automatic recompute.
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

-- Private storage bucket for uploaded permit documents.
-- Path convention: {station_id}/{permit_type}.{ext}
-- Storage RLS policies are added in 0009_rls.sql, alongside the table policies.
insert into storage.buckets (id, name, public)
  values ('permit-documents', 'permit-documents', false)
  on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- Self-approval guards. RLS alone can't restrict which COLUMNS a row
-- owner may change (stations_owner_update/permits_owner in 0009_rls.sql
-- are row-scoped, not column-scoped), so without this a station owner
-- could directly `UPDATE water_stations SET is_accredited = true` or
-- `UPDATE permits SET status = 'approved'` on their own rows, entirely
-- bypassing WASA review. Non-admin callers may still freely change
-- everything else (station name/address, permit storage_path/uploaded_at
-- for re-uploads) -- only the trust-granting columns are locked down.
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
