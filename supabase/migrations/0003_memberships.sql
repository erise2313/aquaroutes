-- Memberships: a profile's role, scoped to an association and (for
-- station_owner/driver) a station. Replaces the flat user_profiles.role
-- string entirely. public_consumer never gets a row here -- anonymous
-- access is handled purely through RLS policies against public views.

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

-- Does the current signed-in user hold an active membership with this role?
create or replace function auth_has_role(check_role app_role) returns boolean as $$
  select exists (
    select 1 from memberships m
    where m.profile_id = auth.uid()
      and m.role = check_role
      and m.status = 'active'
  );
$$ language sql stable security definer set search_path = public;

-- The station the current signed-in user (station_owner or driver) is scoped to.
create or replace function auth_station_id() returns uuid as $$
  select m.station_id from memberships m
  where m.profile_id = auth.uid()
    and m.role in ('station_owner', 'driver')
    and m.status = 'active'
  limit 1;
$$ language sql stable security definer set search_path = public;

-- Station owner self-registration. SECURITY DEFINER so it can insert both
-- the water_stations row and the memberships row atomically, bypassing RLS
-- the sanctioned way -- there is deliberately NO client-insertable RLS
-- policy on memberships (see 0009_rls.sql), and station creation is
-- RPC-only (stations_owner_select/update/delete in 0009_rls.sql grant no
-- owner INSERT). Mirrors register_driver_for_station (0005_workers.sql).
-- Defaults to the single seeded GENTRI WASA association.
-- Idempotent: without this guard, a retried/double-submitted call (slow
-- network, app backgrounded mid-request) would create a second station
-- owned by the same profile -- nothing else stops that, since station_id
-- differs each time and so never collides with the memberships unique
-- constraint. Returns the existing station instead of creating another.
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

-- Customer self-registration. Same reasoning as register_station_owner --
-- there is deliberately no client-insertable RLS policy on memberships, so
-- a raw client-side insert would fail. Idempotent: a second call for an
-- account that already has any membership is a silent no-op rather than a
-- duplicate row (profile_id/association_id/role/station_id is unique, but
-- station_id is NULL for every customer, and Postgres treats NULLs as
-- distinct for uniqueness -- so without this guard a double-tap on
-- "Register" could otherwise create two public_consumer rows).
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
