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

-- =====================================================================
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when ok then 'ok' else 'NOT APPLIED' end as result from (values
  ('auth_is_superadmin', exists (select 1 from pg_proc where proname = 'auth_is_superadmin')),
  ('membership guard', exists (select 1 from pg_trigger where tgname = 'trg_guard_membership_change')),
  ('super admin tools', (select count(*) from pg_proc where proname in ('superadmin_find_account', 'superadmin_set_role', 'superadmin_transfer_station')) = 3),
  ('incident conflict guard', exists (select 1 from pg_trigger where tgname = 'trg_prevent_conflicted_incident_decision')),
  ('association settings', exists (select 1 from association_settings)),
  ('staff functions', (select count(*) from pg_proc where proname in ('register_staff_for_station', 'owner_list_staff', 'owner_remove_staff', 'owner_regenerate_staff_code')) = 4),
  ('staff read policies', (select count(*) from pg_policies where policyname like '%staff_read') = 5),
  ('invite expiry column', exists (select 1 from information_schema.columns where table_name = 'water_stations' and column_name = 'invite_code_expires_at'))
) as t(item, ok);
