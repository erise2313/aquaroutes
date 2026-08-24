-- Worker Security Registry: central clearance record for drivers/helpers,
-- independent of station and shared association-wide so a worker who
-- leaves one station carries their history to the next.
-- Worker codes follow GW-WRK-YYYY-XXXX.

create type clearance_status as enum ('pending_clearance', 'cleared', 'flagged');

create sequence worker_code_seq;

create or replace function generate_worker_code() returns text as $$
  select 'GW-WRK-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('worker_code_seq')::text, 4, '0');
$$ language sql;

create table workers (
  id uuid primary key default gen_random_uuid(),
  -- Nullable: a worker between stations (left/removed, not yet re-linked)
  -- has no current station -- their identity/clearance/incident history
  -- persists regardless (see worker_station_history below). `on delete set
  -- null` (not cascade): deleting a station must not delete the worker or
  -- cascade into their incident/credential/history records -- it should
  -- only unlink them, same as the existing leave/switch-station flows.
  station_id uuid references water_stations(id) on delete set null,
  -- Nullable: a worker can be registered/flagged before they ever have an app login.
  profile_id uuid references profiles(id),
  worker_code text not null unique default generate_worker_code(),
  full_name text not null,
  role_title text not null default 'driver/helper',
  -- Kept on the worker record itself (not just profiles.phone_number) since
  -- a worker can be registered/dispatched before they ever have an app login.
  phone_number text,
  vehicle_plate text,
  jug_capacity int,
  clearance_status clearance_status not null default 'pending_clearance',
  -- Signed payload embedded in the worker's QR clearance badge.
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
  -- e.g. 'missing_cash', 'lost_jugs', 'other'
  incident_type text not null,
  description text not null,
  amount_involved numeric(10,2),
  status incident_status not null default 'pending_review',
  -- set null (not restrict): if the reviewing admin's profile is ever
  -- deleted, the incident record itself should still survive.
  resolved_by uuid references profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index worker_incidents_worker_idx on worker_incidents (worker_id);

-- Filing an incident immediately knocks a 'cleared' worker back to
-- 'pending_clearance' -- it does NOT flag them outright; only a WASA
-- admin confirming the incident does that (see below).
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

-- A WASA admin confirming an incident is what actually flags the worker.
-- Dismissing only clears the worker if this was their LAST outstanding
-- confirmed incident -- otherwise a worker flagged by two different
-- stations would get fully un-flagged the moment just one gets dismissed,
-- leaving the record contradicting its own incident history.
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

-- ---------------------------------------------------------------------
-- Station history: which station(s) a worker has been affiliated with,
-- over time. Exactly one 'active' row per worker at once (enforced by the
-- partial unique index below) -- this is what makes "leave"/"switch"
-- station meaningful instead of just overwriting workers.station_id with
-- no trace of where they worked before.
-- ---------------------------------------------------------------------
create type station_history_status as enum ('active', 'left', 'removed');

create table worker_station_history (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  station_id uuid not null references water_stations(id),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  status station_history_status not null default 'active',
  -- Who ended this affiliation -- the worker themselves (self-leave) or the
  -- station owner (removed from roster).
  ended_by_profile_id uuid references profiles(id)
);

create index worker_station_history_worker_idx on worker_station_history (worker_id);
create index worker_station_history_station_idx on worker_station_history (station_id);
create unique index worker_station_history_one_active on worker_station_history (worker_id) where status = 'active';

-- ---------------------------------------------------------------------
-- Worker credentials (Government ID, Driver's License) -- mirrors the
-- Permit Vault pattern in 0004_permits.sql exactly, including reusing the
-- same permit_status enum, so WASA has something concrete to review
-- before a new driver can be cleared.
-- ---------------------------------------------------------------------
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

-- Both credentials approved -> worker becomes cleared, UNLESS already
-- flagged (an incident-driven flag always takes priority over paperwork)
-- OR they have an unresolved incident under review -- otherwise routine
-- credential paperwork (e.g. re-approving a renewed license) would
-- silently clear a worker mid-investigation, defeating the clearance hold.
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

insert into storage.buckets (id, name, public)
  values ('worker-credentials', 'worker-credentials', false)
  on conflict (id) do nothing;

-- Mirrors prevent_owner_self_permit_approval (0004_permits.sql): a worker
-- may freely re-upload their own credential documents (storage_path/
-- uploaded_at, and moving status to pending_review to submit for review),
-- but only WASA admin may approve one.
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

-- ---------------------------------------------------------------------
-- RPCs for registration/switching/leaving -- all security definer with
-- the authorization check embedded in the function body (same pattern as
-- confirm_jug_settlement in 0007_jug_clearinghouse.sql), since these
-- mutate multiple tables atomically and/or need to bypass a single
-- table's RLS for a narrowly-scoped, well-audited purpose.
-- ---------------------------------------------------------------------

-- Called once, right after auth.signUp(), for the driver registration
-- path -- replaces the old client-side raw workers+memberships inserts so
-- initial registration and later station-switching share one code path.
-- Idempotent: a retried call for a profile that already has a worker row
-- (workers_profile_unique_active, above) returns the existing worker
-- instead of hitting a raw unique-violation error.
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

-- Existing driver switching to a different station. Immediate for
-- cleared/pending_clearance workers; blocked outright for flagged workers
-- -- this is the actual anti-abuse mechanism this whole feature exists for.
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

-- Driver self-service unlink (e.g. quitting).
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

-- Station owner removing a worker from their own roster.
create or replace function owner_remove_worker(p_worker_id uuid) returns void as $$
declare
  v_station_id uuid;
  v_profile_id uuid;
begin
  select station_id, profile_id into v_station_id, v_profile_id from workers where id = p_worker_id;

  -- Explicit NULL-safe check: `x <> auth_station_id()` evaluates to NULL
  -- (not true) when the caller has no station membership, which would
  -- otherwise skip this exception entirely and let ANY signed-in user
  -- detach ANY worker from ANY station.
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

-- Hire Check: cross-station search by name or worker code. Deliberately
-- bypasses workers' normal per-station RLS (via security definer) since
-- this is inherently a cross-station lookup -- the role check below is
-- the actual gate, and it only ever returns a summary (status + confirmed
-- incident count), never incident descriptions/amounts from other stations.
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
