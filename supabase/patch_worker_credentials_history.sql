-- =====================================================================
-- Incremental patch: worker credentials, station history, Hire Check,
-- unlinking. Additive to your existing schema -- no data loss. Safe to
-- run once against the project you already seeded.
-- =====================================================================

-- 1. Allow a worker to be currently unaffiliated (unlinked/between stations).
alter table workers alter column station_id drop not null;

-- 2. Station history table.
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

-- Backfill: give every existing currently-linked worker an 'active' history
-- row (the trigger below only fires for NEW workers going forward).
insert into worker_station_history (worker_id, station_id)
select id, station_id from workers where station_id is not null;

-- 3. Worker credentials table (mirrors permits' shape, reuses permit_status).
create type worker_credential_type as enum ('government_id', 'drivers_license');

create table worker_credentials (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid not null references workers(id) on delete cascade,
  credential_type worker_credential_type not null,
  storage_path text,
  status permit_status not null default 'missing',
  reviewed_by uuid references profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  uploaded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (worker_id, credential_type)
);

create index worker_credentials_worker_idx on worker_credentials (worker_id);

-- Backfill: create the 2 required credential rows for every existing worker.
-- Explicit ::worker_credential_type casts are required here -- inside a
-- UNION ALL, a bare string literal defaults to `text` rather than picking
-- up the eventual INSERT target column's enum type (unlike a plain
-- INSERT ... VALUES, which infers it automatically).
insert into worker_credentials (worker_id, credential_type)
select id, 'government_id'::worker_credential_type from workers
union all
select id, 'drivers_license'::worker_credential_type from workers
on conflict (worker_id, credential_type) do nothing;

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

  if all_ok then
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

-- 4. RPC functions.
create or replace function register_driver_for_station(
  p_invite_code text, p_full_name text, p_phone_number text, p_vehicle_plate text, p_jug_capacity int
) returns uuid as $$
declare v_station_id uuid; v_association_id uuid; v_worker_id uuid;
begin
  select id, association_id into v_station_id, v_association_id from water_stations where invite_code ilike p_invite_code;
  if v_station_id is null then raise exception 'Invalid station invite code.'; end if;

  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity)
    values (v_station_id, auth.uid(), p_full_name, p_phone_number, p_vehicle_plate, p_jug_capacity)
    returning id into v_worker_id;

  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_station_id);
  insert into memberships (profile_id, association_id, role, station_id) values (auth.uid(), v_association_id, 'driver', v_station_id);

  return v_worker_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function driver_switch_station(p_invite_code text) returns void as $$
declare v_worker_id uuid; v_clearance clearance_status; v_new_station_id uuid; v_association_id uuid;
begin
  select id, clearance_status into v_worker_id, v_clearance from workers where profile_id = auth.uid();
  if v_worker_id is null then raise exception 'No worker record found for this account.'; end if;
  if v_clearance = 'flagged' then
    raise exception 'Cannot switch stations while flagged. Contact WASA to resolve outstanding incidents.';
  end if;

  select id, association_id into v_new_station_id, v_association_id from water_stations where invite_code ilike p_invite_code;
  if v_new_station_id is null then raise exception 'Invalid station invite code.'; end if;

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
  if v_worker_id is null then raise exception 'No worker record found for this account.'; end if;

  update workers set station_id = null, updated_at = now() where id = v_worker_id;
  update memberships set station_id = null where profile_id = auth.uid() and role = 'driver';
  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function owner_remove_worker(p_worker_id uuid) returns void as $$
declare v_station_id uuid; v_profile_id uuid;
begin
  select station_id, profile_id into v_station_id, v_profile_id from workers where id = p_worker_id;
  if v_station_id is null or v_station_id <> auth_station_id() then
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
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then raise exception 'Not authorized.'; end if;
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
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then raise exception 'Not authorized.'; end if;
  return query
    select s.station_name, h.joined_at, h.left_at, h.status
    from worker_station_history h join water_stations s on s.id = h.station_id
    where h.worker_id = p_worker_id
    order by h.joined_at desc;
end;
$$ language plpgsql security definer set search_path = public;

-- 5. RLS.
alter table worker_station_history enable row level security;
alter table worker_credentials enable row level security;

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
    select w.id from workers w join water_stations s on s.id = w.station_id where s.owner_profile_id = auth.uid()
  ));
create policy worker_credentials_admin on worker_credentials for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy worker_credentials_self_all on storage.objects for all
  using (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (select id from workers where profile_id = auth.uid())
  )
  with check (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (select id from workers where profile_id = auth.uid())
  );
create policy worker_credentials_admin_read on storage.objects for select
  using (bucket_id = 'worker-credentials' and auth_has_role('wasa_admin'));
