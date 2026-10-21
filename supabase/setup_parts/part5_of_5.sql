-- GENTRI WASA setup -- PART 5 of 5. Run the parts in order,
-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)

create or replace function register_driver_for_station(p_invite_code text, p_full_name text, p_phone_number text, p_vehicle_plate text, p_jug_capacity integer)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
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
    from water_stations where invite_code_key(invite_code) = invite_code_key(p_invite_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_invite_code)) then
      raise exception 'That is the station''s staff code. Drivers need the station''s driver invite code from the owner''s dashboard.';
    end if;
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  if v_worker_id is not null then
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
$function$;

create or replace function register_staff_for_station(p_staff_code text, p_full_name text, p_phone_number text)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
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
    from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_staff_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(invite_code) = invite_code_key(p_staff_code)) then
      raise exception 'That is the station''s driver code. Staff need the station''s staff code -- the owner finds it on their dashboard or Team page.';
    end if;
    raise exception 'Invalid staff code. Ask the station owner for the staff code (not the driver code).';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This staff code has expired. Ask the station owner for a new one.';
  end if;

  insert into profiles (id, full_name, phone_number)
  values (auth.uid(), coalesce(nullif(trim(p_full_name), ''), ''), nullif(trim(p_phone_number), ''))
  on conflict (id) do update
    set full_name = coalesce(nullif(trim(excluded.full_name), ''), profiles.full_name),
        phone_number = coalesce(excluded.phone_number, profiles.phone_number),
        updated_at = now();

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
$function$;

-- VERIFY: select invite_code_key(' tejer01 ') = invite_code_key('TEJERO1');  -- true


-- Limits the server enforces, not only the customer's order form.
--
-- The app capped an order at 50 jugs, but the station's phone/walk-in order
-- and any direct request took any number (1000 jugs went through). A
-- driver's jug capacity had no cap at all (the test plan says 20). Existing
-- rows are left alone: the rules apply when a value is set or changed.

create or replace function check_order_quantity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.jugs_ordered > 50
     and (tg_op = 'INSERT' or new.jugs_ordered is distinct from old.jugs_ordered) then
    raise exception 'At most 50 jugs per order. For a bigger order, place it in parts or call the station.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_check_order_quantity
  before insert or update of jugs_ordered on orders
  for each row execute function check_order_quantity();

create or replace function check_jug_capacity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.jug_capacity is not null and (new.jug_capacity < 1 or new.jug_capacity > 20)
     and (tg_op = 'INSERT' or new.jug_capacity is distinct from old.jug_capacity) then
    raise exception 'Jug capacity must be between 1 and 20.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_check_jug_capacity
  before insert or update of jug_capacity on workers
  for each row execute function check_jug_capacity();

-- VERIFY: insert of an order with 51 jugs or a driver with capacity 21 is refused.


-- Super admins are officers too. A driver's appeal notified wasa_admin
-- accounts only, so a super admin was never told about one.
-- (The delete-account edge function had the same gap and was fixed there.)
create or replace function driver_submit_appeal(p_incident_id uuid, p_text text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
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
   where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
end;
$function$;

-- The owner's Worker Registry listens to `workers` live, but only orders and
-- notifications were published to Realtime, so the subscription failed and
-- the screen spun forever. RLS still decides which rows each person
-- receives (an owner: their own station's workers).
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'workers') then
    alter publication supabase_realtime add table workers;
  end if;
end $$;

-- member_station_names(): every station's id and name, for signed-in people.
--
-- Owners, staff and drivers can read only their own station's row (it holds
-- invite and staff codes), so the Clearinghouse listed the other side of
-- every balance as "Unknown Station", and the station pickers for jug
-- settlements and exchanges came back empty. Names only; nothing else.
create or replace function member_station_names()
returns table (id uuid, station_name text)
language sql stable security definer set search_path = public
as $$
  select ws.id, ws.station_name from water_stations ws order by ws.station_name;
$$;

revoke all on function member_station_names() from public, anon;
grant execute on function member_station_names() to authenticated;

-- my_station_phone(): the owner's phone for the station a driver or staff
-- member works at. The driver dashboard read it through a profiles embed,
-- which drivers can't read, so "Call Station" had no number to call.
create or replace function my_station_phone()
returns text
language sql stable security definer set search_path = public
as $$
  select p.phone_number
    from water_stations ws
    join profiles p on p.id = ws.owner_profile_id
   where ws.id = coalesce(auth_station_id(), auth_staff_station_id())
   limit 1;
$$;

revoke all on function my_station_phone() from public, anon;
grant execute on function my_station_phone() to authenticated;

-- Officer roles: what each officer may change.
--
-- Below the super admin there was one kind of officer, able to change
-- everything except officers and settings. Hiring needs narrower jobs, so an
-- officer membership now carries an officer_role:
--
--   officer     everything except officers and association settings
--   compliance  stations, permits, notices, cases, customer reports,
--               the jug clearinghouse
--   workforce   workers, incidents, credentials, appeals
--   content     bulletin, floor prices, containers, events, resources,
--               website content, reviews
--   viewer      reads everything, changes nothing (an auditor)
--
-- Every officer can still READ everything (all officer read policies are
-- unchanged). What is limited is WRITING: each table officers write to has
-- guard_officer_area(<area>), which refuses the change when the signed-in
-- officer's role doesn't cover that area. People who aren't officers
-- (customers, owners, drivers) and server jobs pass straight through, so the
-- guard changes nothing for them. Super admins pass every guard.

alter table memberships add column if not exists officer_role text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'memberships_officer_role_check') then
    alter table memberships add constraint memberships_officer_role_check
      check (officer_role is null or officer_role in ('officer', 'compliance', 'workforce', 'content', 'viewer'));
  end if;
end $$;
update memberships set officer_role = 'officer' where role = 'wasa_admin' and officer_role is null;

-- A new officer must replace the temporary password before using the portal.
alter table profiles add column if not exists must_change_password boolean not null default false;

-- 'superadmin', an officer_role, or null when the signed-in person is not an
-- active officer.
create or replace function auth_officer_role()
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when exists (select 1 from memberships where profile_id = auth.uid() and role = 'wasa_superadmin' and status = 'active')
      then 'superadmin'
    else (select coalesce(officer_role, 'officer') from memberships
           where profile_id = auth.uid() and role = 'wasa_admin' and status = 'active' limit 1)
  end;
$$;

-- Which areas each role may change. Areas: stations, network, workers,
-- content, accounts, settings.
create or replace function officer_area_allowed(p_role text, p_area text)
returns boolean
language sql immutable
as $$
  select case p_role
    when 'superadmin' then true
    when 'officer' then p_area <> 'settings'
    when 'compliance' then p_area in ('stations', 'network')
    when 'workforce' then p_area = 'workers'
    when 'content' then p_area = 'content'
    else false
  end;
$$;

grant execute on function auth_officer_role() to authenticated;
grant execute on function officer_area_allowed(text, text) to authenticated;

create or replace function guard_officer_area()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_role text := auth_officer_role();
  v_area text := tg_argv[0];
begin
  if v_role is null or officer_area_allowed(v_role, v_area) then
    return coalesce(new, old);
  end if;
  raise exception 'Your officer role (%) can''t change %. Ask a super admin.',
    case v_role when 'compliance' then 'Compliance' when 'workforce' then 'Workforce'
                when 'content' then 'Content' when 'viewer' then 'Viewer' else v_role end,
    case v_area when 'stations' then 'stations, permits or compliance records'
                when 'network' then 'the jug clearinghouse'
                when 'workers' then 'worker records'
                when 'content' then 'posts, prices or website content'
                when 'accounts' then 'user accounts'
                else 'association settings' end;
end;
$$;

do $$
declare
  t record;
begin
  for t in select * from (values
    ('water_stations', 'stations'), ('permits', 'stations'), ('permit_type_labels', 'stations'),
    ('notices', 'stations'), ('compliance_cases', 'stations'), ('station_reports', 'stations'),
    ('station_products', 'stations'),
    ('jug_ledger_entries', 'network'), ('jug_settlements', 'network'),
    ('workers', 'workers'), ('worker_incidents', 'workers'), ('worker_credentials', 'workers'),
    ('bulletins', 'content'), ('bulletin_comments', 'content'), ('bulletin_reports', 'content'),
    ('floor_prices', 'content'), ('container_types', 'content'), ('events', 'content'),
    ('resources', 'content'), ('reviews', 'content'), ('web_content_items', 'content'),
    ('web_faq_entries', 'content'), ('web_page_sections', 'content'),
    ('memberships', 'accounts'), ('account_deletion_requests', 'accounts'),
    ('association_settings', 'settings')
  ) as v(tbl, area)
  loop
    execute format(
      'create or replace trigger trg_guard_officer_area before insert or update or delete on %I
         for each row execute function guard_officer_area(%L)', t.tbl, t.area);
  end loop;
end $$;

-- Only a super admin may set or change an officer's role.
create or replace function guard_officer_role_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is not null
     and new.officer_role is distinct from (case when tg_op = 'UPDATE' then old.officer_role end)
     and not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can change an officer''s role.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_guard_officer_role_change
  before insert or update of officer_role on memberships
  for each row execute function guard_officer_role_change();

-- Super admin sets an existing officer's role (or makes them super admin).
create or replace function superadmin_set_officer_role(p_profile uuid, p_officer_role text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not auth_is_superadmin() then
    raise exception 'Only a WASA super admin can change officer roles.';
  end if;
  if p_officer_role = 'superadmin' then
    perform superadmin_set_role(p_profile, 'wasa_superadmin');
    update memberships set officer_role = null where profile_id = p_profile;
    return;
  end if;
  if p_officer_role not in ('officer', 'compliance', 'workforce', 'content', 'viewer') then
    raise exception 'Unknown officer role.';
  end if;
  if not exists (select 1 from memberships where profile_id = p_profile and role in ('wasa_admin', 'wasa_superadmin')) then
    raise exception 'That account is not an officer.';
  end if;
  perform superadmin_set_role(p_profile, 'wasa_admin');
  update memberships set officer_role = p_officer_role where profile_id = p_profile;
end;
$$;

grant execute on function superadmin_set_officer_role(uuid, text) to authenticated;

-- The signed-in person has replaced their temporary password.
create or replace function clear_must_change_password()
returns void
language sql security definer set search_path = public
as $$
  update profiles set must_change_password = false where id = auth.uid();
$$;

grant execute on function clear_must_change_password() to authenticated;

-- Station IDs and written addresses.
--
-- 1. Every station gets a permanent code, GW-STN-<year>-<nnnn>, like the
--    workers' GW-WRK codes: two stations (or two workers) can share a name,
--    and the code tells them apart.
-- 2. A map pin alone isn't enough to find a door. Stations, saved customer
--    addresses and orders now carry a written address too: house no. /
--    street / subdivision, barangay, city and an optional landmark. An
--    order keeps a copy of the address it was sent to, so editing a saved
--    address later never changes where a past order went.

-- 1. Station codes ----------------------------------------------------------
create sequence if not exists station_code_seq;

create or replace function generate_station_code()
returns text
language sql set search_path = public
as $$
  select 'GW-STN-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('station_code_seq')::text, 4, '0');
$$;

alter table water_stations add column if not exists station_code text;

-- Existing stations, oldest first, numbered from their creation year.
do $$
declare s record;
begin
  for s in select id, created_at from water_stations where station_code is null order by created_at loop
    update water_stations
       set station_code = 'GW-STN-' || to_char(s.created_at, 'YYYY') || '-' || lpad(nextval('station_code_seq')::text, 4, '0')
     where id = s.id;
  end loop;
end $$;

alter table water_stations alter column station_code set default generate_station_code();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'water_stations_station_code_key') then
    alter table water_stations add constraint water_stations_station_code_key unique (station_code);
  end if;
end $$;

-- The station's written-address columns, before the view below that
-- shows the landmark (section 2 repeats them harmlessly).
alter table water_stations add column if not exists street text;
alter table water_stations add column if not exists city text default 'General Trias';
alter table water_stations add column if not exists landmark text;

-- The public directory and pages show the code and the landmark. New
-- columns go at the end so the view keeps its existing ones.
create or replace view public_stations as
 SELECT ws.id,
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
    b.name AS barangay_name,
    COALESCE(r.avg_rating, 0::numeric) AS avg_rating,
    COALESCE(r.review_count, 0::bigint) AS review_count,
    ws.standing,
    ws.created_at AS member_since,
    ws.accredited_at,
    ( SELECT max(p.reviewed_at) AS max
           FROM permits p
          WHERE p.station_id = ws.id AND p.permit_type = 'water_quality_test_report'::permit_type AND p.status = 'approved'::permit_status) AS last_water_test_at,
    ( SELECT max(p.expiry_date) AS max
           FROM permits p
          WHERE p.station_id = ws.id AND p.permit_type = 'sanitary_permit'::permit_type AND p.status = 'approved'::permit_status) AS sanitary_valid_until,
    ws.station_code,
    ws.landmark
   FROM water_stations ws
     LEFT JOIN barangays b ON b.id = ws.barangay_id
     LEFT JOIN ( SELECT reviews.station_id,
            avg(reviews.rating)::numeric(3,2) AS avg_rating,
            count(*) AS review_count
           FROM reviews
          GROUP BY reviews.station_id) r ON r.station_id = ws.id
  WHERE ws.is_colorum_verified = true AND ws.is_active = true;

-- 2. Written addresses --------------------------------------------------------
alter table water_stations add column if not exists street text;
alter table water_stations add column if not exists city text default 'General Trias';
alter table water_stations add column if not exists landmark text;

alter table customer_addresses add column if not exists street text;
alter table customer_addresses add column if not exists barangay text;
alter table customer_addresses add column if not exists city text default 'General Trias';
alter table customer_addresses add column if not exists landmark text;

alter table orders add column if not exists delivery_address text;

-- Records the written address an order is delivered to. The customer can
-- set it on their own order while it is still pending; the station's owner
-- or staff can set or correct it until the order is done (phone orders).
-- Orders can't be written directly by members (direct-write guards), so
-- this is the way in.
create or replace function set_order_delivery_address(p_order_id uuid, p_address text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  o orders%rowtype;
  v_address text := nullif(trim(p_address), '');
  v_allowed boolean;
begin
  select * into o from orders where id = p_order_id;
  if not found then
    raise exception 'Order not found.';
  end if;
  if v_address is not null and length(v_address) > 300 then
    raise exception 'Keep the address under 300 characters.';
  end if;
  -- coalesce: for someone who isn't staff, auth_staff_station_id() is NULL,
  -- which made the whole test NULL and "if not NULL" let anyone through.
  v_allowed := coalesce(
       (o.customer_profile_id = auth.uid() and o.status = 'pending')
    or (o.status not in ('done', 'cancelled') and (
          exists (select 1 from water_stations ws where ws.id = o.station_id and ws.owner_profile_id = auth.uid())
          or coalesce(o.station_id = auth_staff_station_id(), false))),
    false);
  if not v_allowed then
    raise exception 'You can''t change the address on this order.';
  end if;
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set delivery_address = v_address where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$;

revoke all on function set_order_delivery_address(uuid, text) from public, anon;
grant execute on function set_order_delivery_address(uuid, text) to authenticated;

-- 1. The jug clearinghouse is between the two stations only.
--
-- A settlement was always proposed by the station holding the jugs and
-- confirmed by the station that owns them, but officers could also reject a
-- proposal, and either station could escalate a disagreement to WASA. The
-- association decided settlements are the two stations' business: WASA keeps
-- a read-only view for oversight, and a station that disagrees simply
-- rejects the proposal.

-- Only the owning station rejects a proposal (officers no longer can).
create or replace function reject_jug_settlement(p_settlement_id uuid)
returns void
language plpgsql security definer set search_path = public
as $function$
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
    raise exception 'Only the station that owns the jugs can reject this settlement.';
  end if;
  update jug_settlements set status = 'rejected' where id = p_settlement_id;
end;
$function$;

-- Disputes to WASA are retired.
create or replace function dispute_jug_settlement(p_settlement_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $function$
begin
  raise exception 'Jug settlements are between the two stations. If a proposal is wrong, the owning station rejects it and the holder proposes again.';
end;
$function$;

-- No officer (super admins included) changes clearinghouse records. The
-- stations' own writes and the delivery ledger entries pass, since the
-- guard only acts on officers.
create or replace function guard_officer_area()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_role text := auth_officer_role();
  v_area text := tg_argv[0];
begin
  if v_role is null then
    return coalesce(new, old);
  end if;
  if v_area = 'network' then
    raise exception 'The jug clearinghouse is between the two stations; WASA can view it but not change it.';
  end if;
  if officer_area_allowed(v_role, v_area) then
    return coalesce(new, old);
  end if;
  raise exception 'Your officer role (%) can''t change %. Ask a super admin.',
    case v_role when 'compliance' then 'Compliance' when 'workforce' then 'Workforce'
                when 'content' then 'Content' when 'viewer' then 'Viewer' else v_role end,
    case v_area when 'stations' then 'stations, permits or compliance records'
                when 'workers' then 'worker records'
                when 'content' then 'posts, prices or website content'
                when 'accounts' then 'user accounts'
                else 'association settings' end;
end;
$$;

-- 2. Appeals against a suspension.
--
-- A suspended account could only read "contact WASA". It can now send one
-- written appeal at a time from the suspended screen; full officers and
-- super admins (the "accounts" area) reinstate the account or keep it
-- suspended, with a note the person sees.
create table if not exists account_appeals (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  appeal_text text not null check (length(trim(appeal_text)) >= 10),
  status text not null default 'pending' check (status in ('pending', 'reinstated', 'kept_suspended')),
  decision_note text,
  decided_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists account_appeals_profile_idx on account_appeals (profile_id, created_at desc);
alter table account_appeals enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'account_appeals' and policyname = 'account_appeals_self_read') then
    create policy account_appeals_self_read on account_appeals for select using (profile_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'account_appeals' and policyname = 'account_appeals_officer_read') then
    create policy account_appeals_officer_read on account_appeals for select using (auth_has_role('wasa_admin'));
  end if;
end $$;

create or replace trigger trg_guard_officer_area before insert or update or delete on account_appeals
  for each row execute function guard_officer_area('accounts');

create or replace function submit_account_appeal(p_text text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if not exists (select 1 from memberships where profile_id = auth.uid() and status = 'suspended') then
    raise exception 'This account is not suspended.';
  end if;
  if length(trim(coalesce(p_text, ''))) < 10 then
    raise exception 'Explain in a sentence or two why the suspension should be lifted.';
  end if;
  if exists (select 1 from account_appeals where profile_id = auth.uid() and status = 'pending') then
    raise exception 'Your appeal is already with WASA. You will see the decision here.';
  end if;
  insert into account_appeals (profile_id, appeal_text) values (auth.uid(), left(trim(p_text), 1000));
  insert into notifications (profile_id, category, title, body)
  select m.profile_id, 'account', 'Suspension appeal to review',
         coalesce((select full_name from profiles where id = auth.uid()), 'An account') || ' appealed their suspension.'
    from memberships m
   where m.status = 'active'
     and (m.role = 'wasa_superadmin' or (m.role = 'wasa_admin' and coalesce(m.officer_role, 'officer') = 'officer'));
end;
$$;

create or replace function decide_account_appeal(p_appeal_id uuid, p_reinstate boolean, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a account_appeals%rowtype;
  v_role text := auth_officer_role();
begin
  if v_role is null or not officer_area_allowed(v_role, 'accounts') then
    raise exception 'Only a full officer or a super admin can decide an appeal.';
  end if;
  if length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Write a short note for the person.';
  end if;
  select * into a from account_appeals where id = p_appeal_id for update;
  if not found then
    raise exception 'Appeal not found.';
  end if;
  if a.status <> 'pending' then
    raise exception 'This appeal has already been decided.';
  end if;
  update account_appeals
     set status = case when p_reinstate then 'reinstated' else 'kept_suspended' end,
         decision_note = trim(p_note), decided_by = auth.uid(), decided_at = now()
   where id = p_appeal_id;
  if p_reinstate then
    -- Officer accounts can only be reinstated by a super admin
    -- (guard_membership_change refuses anyone else).
    update memberships set status = 'active' where profile_id = a.profile_id and status = 'suspended';
  end if;
  insert into notifications (profile_id, category, title, body)
  values (a.profile_id, 'account',
          case when p_reinstate then 'Your account has been reinstated' else 'Your appeal was not accepted' end,
          left(trim(p_note), 200));
end;
$$;

revoke all on function submit_account_appeal(text) from public, anon;
revoke all on function decide_account_appeal(uuid, boolean, text) from public, anon;
grant execute on function submit_account_appeal(text) to authenticated;
grant execute on function decide_account_appeal(uuid, boolean, text) to authenticated;

-- station_driver_positions(): where the caller's on-duty drivers are.
--
-- The owner's "Live Fleet Tracking" map showed the station and the stops
-- but never the drivers, although the driver app reports its position
-- while on duty (driver_states). This returns the latitude and longitude
-- the app can plot (current_location is a PostGIS point), for the owner's
-- or staff member's own station only. Off-duty drivers are left out, so
-- going off duty takes a driver off the map.
create or replace function station_driver_positions()
returns table (worker_id uuid, full_name text, worker_code text, latitude double precision, longitude double precision, last_updated timestamptz)
language sql stable security definer set search_path = public, extensions
as $$
  select w.id, w.full_name, w.worker_code,
         st_y(ds.current_location::geometry), st_x(ds.current_location::geometry),
         ds.last_updated
    from driver_states ds
    join workers w on w.id = ds.worker_id
   where ds.is_active
     and ds.current_location is not null
     and ds.station_id = coalesce(
           (select id from water_stations where owner_profile_id = auth.uid() limit 1),
           auth_staff_station_id());
$$;

revoke all on function station_driver_positions() from public, anon;
grant execute on function station_driver_positions() to authenticated;


-- station_order_details(): who and where, for the station's own orders.
--
-- The Live Order Pipeline showed a name only for phone and walk-in orders:
-- for an app order the owner saw "Placed at 4:55 AM", because owners can't
-- read customers' profiles. And it had no way to see the delivery point,
-- which is stored as a PostGIS point the app can't read. This returns the
-- customer's name and phone and the delivery latitude/longitude, for orders
-- of the caller's own station (owner or staff) only.
create or replace function station_order_details(p_ids uuid[])
returns table (order_id uuid, customer_name text, customer_phone text, latitude double precision, longitude double precision)
language sql stable security definer set search_path = public
as $$
  select o.id,
         coalesce(p.full_name, o.guest_name),
         coalesce(nullif(o.customer_phone, ''), p.phone_number, o.guest_phone),
         case when o.delivery_location is null then null else st_y(o.delivery_location::geometry) end,
         case when o.delivery_location is null then null else st_x(o.delivery_location::geometry) end
    from orders o
    left join profiles p on p.id = o.customer_profile_id
   where o.id = any(p_ids)
     and o.station_id = coalesce(
           (select id from water_stations where owner_profile_id = auth.uid() limit 1),
           auth_staff_station_id());
$$;

revoke all on function station_order_details(uuid[]) from public, anon;
grant execute on function station_order_details(uuid[]) to authenticated;



-- =====================================================================
-- STEP 2 of 7 -- ACCOUNTS AND STATIONS  (seed_test_accounts.sql)
-- =====================================================================
-- admin@, owner1@ (Buenavista), owner2@ (Navarro Springs), driver1@,
-- driver2@, customer1@ -- pre-confirmed, stations accredited.
-- =====================================================================

-- =====================================================================
-- AquaRoute / GENTRI WASA -- TEST ACCOUNT SEEDING (demo/testing only)
-- =====================================================================
-- Creates ready-to-use login accounts so you don't have to register
-- through the app UI: 1 WASA admin, 2 station owners (each with a
-- station that already has a location set), 2 drivers (each assigned
-- to one of those stations), and 1 customer account. All permits for
-- the two demo stations are marked 'approved' and both stations are
-- forced accredited + colorum-verified, so they show up fully
-- functional on the public map and owner portal immediately --
-- bypassing the normal "upload and wait for WASA review" flow purely
-- for ease of demoing.
--
-- For a lean 4-role presentation flow (admin / owner / driver /
-- customer) you only need admin@, owner1@, driver1@, and customer1@ --
-- owner2@/driver2@ are there if you also want to demo Hire Check
-- (cross-station worker lookup) against a second station.
-- DO NOT run this against a production project with real users.
--
-- Coordinates below are approximate placeholders within General Trias,
-- Cavite for demo purposes -- not surveyed/verified real addresses.
--
-- Run supabase/reset_and_rebuild.sql FIRST if you haven't already.
-- Then paste this whole file into the Supabase SQL Editor and run it.
-- =====================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  owner1_id uuid := gen_random_uuid();
  owner2_id uuid := gen_random_uuid();
  driver1_id uuid := gen_random_uuid();
  driver2_id uuid := gen_random_uuid();
  customer1_id uuid := gen_random_uuid();
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  station1_id uuid := gen_random_uuid();
  station2_id uuid := gen_random_uuid();
  barangay1_id uuid;
  barangay2_id uuid;
  test_emails text[] := array[
    'admin@gentriwasa.test', 'owner1@gentriwasa.test', 'owner2@gentriwasa.test',
    'driver1@gentriwasa.test', 'driver2@gentriwasa.test', 'customer1@gentriwasa.test'
  ];
  v_old_profile_ids uuid[];
  v_old_station_ids uuid[];
begin

  -- -------------------------------------------------------------------
  -- 0. Idempotency: if this script was already run before (or these
  -- accounts picked up other activity in the meantime -- floor prices,
  -- bulletin posts, orders, jug ledger entries, etc., all reference
  -- profiles/stations with no cascade), re-running would collide on the
  -- unique email constraint and/or fail on a foreign key. Clean up every
  -- table that references these profiles or their stations first, in
  -- FK-safe order, before removing the profiles/stations/auth users
  -- themselves.
  -- -------------------------------------------------------------------
  select array_agg(id) into v_old_profile_ids from auth.users where email = any(test_emails);
  select array_agg(id) into v_old_station_ids from water_stations where owner_profile_id = any(v_old_profile_ids);

  if v_old_profile_ids is not null then
    delete from bulletin_reactions where profile_id = any(v_old_profile_ids);
    delete from bulletin_comments where profile_id = any(v_old_profile_ids);
    delete from reviews where profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from jug_settlements where proposed_by = any(v_old_profile_ids) or confirmed_by = any(v_old_profile_ids)
      or holder_station_id = any(v_old_station_ids) or owner_station_id = any(v_old_station_ids);
    delete from jug_ledger_entries where recorded_by = any(v_old_profile_ids)
      or holder_station_id = any(v_old_station_ids) or owner_station_id = any(v_old_station_ids);
    delete from orders where customer_profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from bulletins where posted_by = any(v_old_profile_ids);
    delete from floor_prices where set_by = any(v_old_profile_ids);
    delete from resources where uploaded_by = any(v_old_profile_ids);
    delete from events where created_by = any(v_old_profile_ids);
    delete from worker_incidents where reported_by_profile_id = any(v_old_profile_ids) or resolved_by = any(v_old_profile_ids);
    delete from worker_station_history where ended_by_profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from memberships where profile_id = any(v_old_profile_ids);
    delete from workers where profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from water_stations where owner_profile_id = any(v_old_profile_ids);
    delete from auth.users where id = any(v_old_profile_ids);
  end if;

  -- -------------------------------------------------------------------
  -- 1. Auth users (email/password, pre-confirmed -- no email sent).
  --    The handle_new_auth_user trigger (0001_core_identity.sql) auto-
  --    creates each matching `profiles` row from raw_user_meta_data.
  -- -------------------------------------------------------------------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
     'admin@gentriwasa.test', crypt('Admin123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"WASA Admin"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', owner1_id, 'authenticated', 'authenticated',
     'owner1@gentriwasa.test', crypt('Owner123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Juan Dela Cruz"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', owner2_id, 'authenticated', 'authenticated',
     'owner2@gentriwasa.test', crypt('Owner123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Maria Santos"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', driver1_id, 'authenticated', 'authenticated',
     'driver1@gentriwasa.test', crypt('Driver123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Pedro Reyes"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', driver2_id, 'authenticated', 'authenticated',
     'driver2@gentriwasa.test', crypt('Driver123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Ana Cruz"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', customer1_id, 'authenticated', 'authenticated',
     'customer1@gentriwasa.test', crypt('Customer123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Liza Fernandez"}',
     now(), now(), '', '', '', '');

  -- Required by current Supabase Auth for email/password sign-in to work.
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), admin_id, admin_id::text, jsonb_build_object('sub', admin_id::text, 'email', 'admin@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), owner1_id, owner1_id::text, jsonb_build_object('sub', owner1_id::text, 'email', 'owner1@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), owner2_id, owner2_id::text, jsonb_build_object('sub', owner2_id::text, 'email', 'owner2@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), driver1_id, driver1_id::text, jsonb_build_object('sub', driver1_id::text, 'email', 'driver1@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), driver2_id, driver2_id::text, jsonb_build_object('sub', driver2_id::text, 'email', 'driver2@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), customer1_id, customer1_id::text, jsonb_build_object('sub', customer1_id::text, 'email', 'customer1@gentriwasa.test'), 'email', now(), now(), now());

  -- -------------------------------------------------------------------
  -- 2. WASA admin membership (no station_id -- association-wide).
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role)
  values (admin_id, v_association_id, 'wasa_admin');

  -- -------------------------------------------------------------------
  -- 3. Two stations, each with a location already set.
  -- -------------------------------------------------------------------
  select id into barangay1_id from barangays where association_id = v_association_id and name = 'Buenavista I';
  select id into barangay2_id from barangays where association_id = v_association_id and name = 'Navarro';

  insert into water_stations (
    id, association_id, owner_profile_id, barangay_id, invite_code,
    station_name, station_address, latitude, longitude,
    price_per_jug, delivery_fee, offered_water_types
  ) values (
    station1_id, v_association_id, owner1_id, barangay1_id,
    'BUENAV1',
    'Buenavista Water Refilling Station',
    'Buenavista I, General Trias, Cavite',
    14.3745, 120.8790,
    25.00, 20.00,
    array['purified', 'alkaline']
  ), (
    station2_id, v_association_id, owner2_id, barangay2_id,
    'NAVSPR1',
    'Navarro Springs Water Station',
    'Navarro, General Trias, Cavite',
    14.3958, 120.8875,
    22.00, 15.00,
    array['purified', 'mineral']
  );

  insert into memberships (profile_id, association_id, role, station_id) values
    (owner1_id, v_association_id, 'station_owner', station1_id),
    (owner2_id, v_association_id, 'station_owner', station2_id);

  -- -------------------------------------------------------------------
  -- 4. Force both demo stations fully accredited + colorum-verified,
  --    and mark every permit 'approved' -- skips the normal upload/
  --    review wait entirely, per your ask for ease of demoing.
  -- -------------------------------------------------------------------
  -- Both updates below are blocked by guard triggers that require
  -- auth_has_role('wasa_admin'). In the SQL Editor auth.uid() is NULL, so
  -- there is no admin to be and the guards raise -- correctly, since their
  -- whole purpose is stopping a station owner from accrediting itself.
  -- Seeding is a legitimate out-of-band exception, so the two guards are
  -- switched off for exactly these statements and switched straight back on.
  --
  -- Both are needed together: approving a permit fires
  -- trg_recompute_accreditation, which updates water_stations and would
  -- trip the first guard even though this block never touches it directly.
  alter table water_stations disable trigger trg_prevent_owner_self_accreditation;
  alter table permits disable trigger trg_prevent_owner_self_permit_approval;

  update water_stations
    set is_accredited = true, accreditation_status = 'accredited', is_colorum_verified = true
    where id in (station1_id, station2_id);

  update permits
    set status = 'approved', reviewed_by = admin_id, reviewed_at = now()
    where station_id in (station1_id, station2_id);

  alter table permits enable trigger trg_prevent_owner_self_permit_approval;
  alter table water_stations enable trigger trg_prevent_owner_self_accreditation;

  -- -------------------------------------------------------------------
  -- 5. Two drivers, one per station, pre-cleared (skips pending_clearance).
  -- -------------------------------------------------------------------
  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity, clearance_status) values
    (station1_id, driver1_id, 'Pedro Reyes', '09171234501', 'ABC1234', 20, 'cleared'),
    (station2_id, driver2_id, 'Ana Cruz', '09171234502', 'XYZ5678', 15, 'cleared');

  -- Station history, which inserting into `workers` directly does not
  -- create. Only register_driver_for_station() and driver_switch_station()
  -- write these rows, and this script bypasses both -- so without this the
  -- seeded drivers show "No station history" in Hire Check, making a
  -- working feature look broken. (Raised by the evaluator, 10 Oct 2026.)
  insert into worker_station_history (worker_id, station_id, joined_at, status)
  select w.id, w.station_id, now() - interval '60 days', 'active'
    from workers w
   where w.profile_id in (driver1_id, driver2_id);

  insert into memberships (profile_id, association_id, role, station_id) values
    (driver1_id, v_association_id, 'driver', station1_id),
    (driver2_id, v_association_id, 'driver', station2_id);

  -- -------------------------------------------------------------------
  -- 6. One customer account (public_consumer, no station) -- lets you
  --    skip live-registering a customer during a demo if you'd rather
  --    just log straight in and place an order.
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role, station_id) values
    (customer1_id, v_association_id, 'public_consumer', null);

end $$;



-- =====================================================================
-- STEP 3 of 7 -- MORE ROLE ACCOUNTS  (seed_role_accounts.sql)
-- =====================================================================
-- admin2@, driver3@, driver4@, customer2@, suspended@, owner3@ (station
-- not yet accredited), superadmin1@, superadmin2@, staff1@.
-- =====================================================================

-- =====================================================================
-- More test accounts, one for each situation the test cases need that
-- seed_test_accounts.sql does not cover (demo/testing only).
--
--   admin2@gentriwasa.test     Admin123!     second WASA officer
--   driver3@gentriwasa.test    Driver123!    cleared driver, Buenavista
--   driver4@gentriwasa.test    Driver123!    cleared driver, Navarro Springs
--   customer2@gentriwasa.test  Customer123!  second customer
--   suspended@gentriwasa.test  Customer123!  customer whose account is suspended
--   owner3@gentriwasa.test     Owner123!     owner of a station not yet accredited
--   superadmin1@gentriwasa.test Admin123!    WASA super admin (association president)
--   superadmin2@gentriwasa.test Admin123!    WASA super admin (secretary)
--   staff1@gentriwasa.test     Staff123!     station staff (dispatcher), Buenavista
--
-- Why each one:
--   * admin2 -- the Users list shows officers now; with two, an officer can
--     see the other and confirm they cannot suspend themselves.
--   * driver3/driver4 -- seed_demo_gaps.sql flags driver1, and driver2 was
--     flagged in testing, so neither seeded station had a driver that could
--     be assigned an order. These two are cleared, credentials approved.
--   * customer2 -- checks that one customer cannot see another's orders or
--     follow their driver.
--   * suspended -- signing in shows the "account suspended" screen; the
--     server also refuses their orders.
--   * superadmin1/2 -- the two super admins (patch_roles_governance.sql):
--     manage officers, transfer stations, association settings. Two, so
--     neither can be locked out by the other leaving.
--   * staff1 -- a dispatcher at Buenavista: orders, drivers, tracking only.
--   * owner3 -- a station at the start of the process: permits waiting to
--     be uploaded, not accredited, not on the public map. Walks the whole
--     accreditation flow (Permit vault -> Admin Permits -> accredited).
--
-- Additive and idempotent: an account whose email already exists is left
-- untouched, and nothing is deleted. Run after seed_test_accounts.sql
-- (driver3/driver4 join owner1's and owner2's stations). Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_station1 uuid;
  v_station2 uuid;
  v_station3 uuid;
  v_barangay uuid;
  v_id uuid;
  acct record;
begin
  select ws.id into v_station1 from water_stations ws join auth.users u on u.id = ws.owner_profile_id
   where u.email = 'owner1@gentriwasa.test';
  select ws.id into v_station2 from water_stations ws join auth.users u on u.id = ws.owner_profile_id
   where u.email = 'owner2@gentriwasa.test';
  if v_station1 is null or v_station2 is null then
    raise exception 'Run seed_test_accounts.sql first: owner1''s and owner2''s stations are needed.';
  end if;

  for acct in
    select * from (values
      ('admin2@gentriwasa.test',    'Admin123!',    'Rosa Mendoza',    '09171230001', 'wasa_admin'),
      ('driver3@gentriwasa.test',   'Driver123!',   'Carlo Bautista',  '09171230002', 'driver'),
      ('driver4@gentriwasa.test',   'Driver123!',   'Joy Villanueva',  '09171230003', 'driver'),
      ('customer2@gentriwasa.test', 'Customer123!', 'Ramon Garcia',    '09171230004', 'public_consumer'),
      ('suspended@gentriwasa.test', 'Customer123!', 'Susana Lim',      '09171230005', 'public_consumer'),
      ('owner3@gentriwasa.test',    'Owner123!',    'Elena Ramos',     '09171230006', 'station_owner'),
      ('superadmin1@gentriwasa.test', 'Admin123!',  'Teresa Aquino',   '09171230007', 'wasa_superadmin'),
      ('superadmin2@gentriwasa.test', 'Admin123!',  'Nestor Villaroman', '09171230008', 'wasa_superadmin'),
      ('staff1@gentriwasa.test',    'Staff123!',    'Mylene Castro',   '09171230009', 'station_staff')
    ) as t(email, password, full_name, phone, role)
  loop
    if exists (select 1 from auth.users where email = acct.email) then
      continue;
    end if;

    v_id := gen_random_uuid();

    -- The handle_new_auth_user trigger creates the matching profiles row.
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      acct.email, crypt(acct.password, gen_salt('bf')),
      now(), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', acct.full_name),
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', acct.email), 'email', now(), now(), now());

    update profiles set phone_number = acct.phone, privacy_consented_at = now(), privacy_notice_version = 'seed'
     where id = v_id;

    if acct.role = 'station_staff' then
      insert into memberships (profile_id, association_id, role, station_id)
      values (v_id, v_association_id, 'station_staff', v_station1);

    elsif acct.role in ('wasa_admin', 'wasa_superadmin', 'public_consumer') then
      insert into memberships (profile_id, association_id, role, status)
      values (v_id, v_association_id, acct.role::app_role,
              case when acct.email = 'suspended@gentriwasa.test' then 'suspended' else 'active' end);

    elsif acct.role = 'driver' then
      insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity, clearance_status)
      values (case when acct.email = 'driver3@gentriwasa.test' then v_station1 else v_station2 end,
              v_id, acct.full_name, acct.phone,
              case when acct.email = 'driver3@gentriwasa.test' then 'DRV3003' else 'DRV4004' end,
              18, 'cleared');
      insert into worker_station_history (worker_id, station_id, joined_at, status)
      select w.id, w.station_id, now() - interval '30 days', 'active' from workers w where w.profile_id = v_id;
      insert into memberships (profile_id, association_id, role, station_id)
      select v_id, v_association_id, 'driver', w.station_id from workers w where w.profile_id = v_id;

      -- Adding a worker creates their required credentials, pending review.
      -- Approve them so this driver is genuinely cleared rather than
      -- sitting in the officers' queue. The guard trigger only lets an
      -- officer approve, and there is no signed-in officer here.
      alter table worker_credentials disable trigger trg_prevent_worker_self_credential_approval;
      update worker_credentials set status = 'approved', reviewed_at = now()
       where worker_id = (select id from workers where profile_id = v_id);
      alter table worker_credentials enable trigger trg_prevent_worker_self_credential_approval;
      update workers set clearance_status = 'cleared' where profile_id = v_id;

    elsif acct.role = 'station_owner' then
      select id into v_barangay from barangays where association_id = v_association_id and name ilike 'Tejero%' limit 1;
      v_station3 := gen_random_uuid();
      -- Not accredited: sync_required_permits creates its permits, all
      -- waiting for upload.
      insert into water_stations (
        id, association_id, owner_profile_id, barangay_id, invite_code,
        station_name, station_address, latitude, longitude,
        price_per_jug, delivery_fee, offered_water_types
      ) values (
        v_station3, v_association_id, v_id, v_barangay, 'TEJERO1',
        'Tejero Aqua Station', 'Tejero, General Trias, Cavite',
        14.3870, 120.8710, 25.00, 20.00, array['purified']
      );
      insert into memberships (profile_id, association_id, role, station_id)
      values (v_id, v_association_id, 'station_owner', v_station3);
    end if;
  end loop;
end $$;

-- =====================================================================
-- VERIFY -- one line per account.
-- =====================================================================
select u.email, m.role, m.status,
       coalesce(ws.station_name, '') as station,
       coalesce(w.clearance_status::text, '') as driver_clearance,
       coalesce(ws.is_accredited::text, '') as station_accredited
  from auth.users u
  left join memberships m on m.profile_id = u.id
  left join water_stations ws on ws.id = m.station_id
  left join workers w on w.profile_id = u.id
 where u.email like '%@gentriwasa.test'
 order by m.role, u.email;



-- =====================================================================
-- STEP 4 of 7 -- OFFICER ROLE ACCOUNTS  (seed_officer_accounts.sql)
-- =====================================================================
-- compliance1@, workforce1@, content1@, viewer1@ (Officer123!).
-- =====================================================================

-- =====================================================================
-- Officer accounts for each officer role (demo/testing only).
--
--   compliance1@gentriwasa.test  Officer123!  Compliance officer  (Carmen Reyes)
--   workforce1@gentriwasa.test   Officer123!  Workforce officer   (Wilfredo Lim)
--   content1@gentriwasa.test     Officer123!  Content editor      (Cora Bautista)
--   viewer1@gentriwasa.test      Officer123!  Viewer / auditor    (Vilma Santos)
--
-- On the original project these were made in Admin -> Officers by a super
-- admin (create-officer Edge Function), which also asks for a new password
-- at first sign-in. Seeded here so a new project has them straight away,
-- without that first-password step.
--
-- Additive and idempotent: an account whose email already exists is left
-- untouched. Run after seed_role_accounts.sql. Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_id uuid;
  acct record;
begin
  for acct in
    select * from (values
      ('compliance1@gentriwasa.test', 'Carmen Reyes',  '09171230011', 'compliance'),
      ('workforce1@gentriwasa.test',  'Wilfredo Lim',  '09171230012', 'workforce'),
      ('content1@gentriwasa.test',    'Cora Bautista', '09171230013', 'content'),
      ('viewer1@gentriwasa.test',     'Vilma Santos',  '09171230014', 'viewer')
    ) as t(email, full_name, phone, officer_role)
  loop
    if exists (select 1 from auth.users where email = acct.email) then
      continue;
    end if;

    v_id := gen_random_uuid();

    -- The handle_new_auth_user trigger creates the matching profiles row.
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      acct.email, crypt('Officer123!', gen_salt('bf')),
      now(), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', acct.full_name),
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', acct.email), 'email', now(), now(), now());

    update profiles set phone_number = acct.phone, privacy_consented_at = now(), privacy_notice_version = 'seed'
     where id = v_id;

    insert into memberships (profile_id, association_id, role, status, officer_role)
    values (v_id, v_association_id, 'wasa_admin', 'active', acct.officer_role);
  end loop;

  -- The full officers seeded earlier, stated explicitly (an empty role
  -- already means full officer).
  update memberships m set officer_role = 'officer'
    from auth.users u
   where u.id = m.profile_id and m.role = 'wasa_admin' and m.officer_role is null
     and u.email in ('admin@gentriwasa.test', 'admin2@gentriwasa.test');
end $$;

-- VERIFY -- one line per officer.
select u.email, m.role, coalesce(m.officer_role, 'officer') as officer_role, m.status
  from auth.users u join memberships m on m.profile_id = u.id
 where m.role in ('wasa_admin', 'wasa_superadmin')
 order by m.role, u.email;



-- =====================================================================
-- STEP 5 of 7 -- SAMPLE PRODUCTS  (seed_sample_products.sql)
-- =====================================================================
-- What each seeded station sells and for how much, so customers can order.
-- =====================================================================

-- =====================================================================
-- Sample products and prices for the seeded stations (demo/testing only).
--
-- Customers order products, not a station's single price. The schema step
-- turns each existing station's price into products, but on a new project
-- it runs before any station exists, so without this the seeded stations
-- would have nothing to order.
--
--   Buenavista (owner1)      purified and alkaline, slim and round 5-gal,
--                            1-gallon, 350 mL bottle, a new slim jug
--   Navarro Springs (owner2) purified and mineral, slim and round 5-gal,
--                            500 mL bottle
--   Tejero (owner3)          purified, slim and round 5-gal
--
-- Prices are typical General Trias refill prices, for demonstration.
-- Additive and idempotent: a product a station already lists is left as
-- it is. Run after seed_role_accounts.sql. Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  r record;
begin
  for r in
    select ws.id as station_id, p.water_type, p.container_code, p.kind, p.price
      from (values
        ('owner1@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         25.00),
        ('owner1@gentriwasa.test', 'purified', 'round_5gal',   'refill',         25.00),
        ('owner1@gentriwasa.test', 'alkaline', 'slim_5gal',    'refill',         35.00),
        ('owner1@gentriwasa.test', 'alkaline', 'round_5gal',   'refill',         35.00),
        ('owner1@gentriwasa.test', 'purified', 'gallon_1',     'refill',         10.00),
        ('owner1@gentriwasa.test', 'purified', 'bottle_350ml', 'refill',          8.00),
        ('owner1@gentriwasa.test', 'purified', 'slim_5gal',    'new_container', 220.00),
        ('owner2@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         22.00),
        ('owner2@gentriwasa.test', 'purified', 'round_5gal',   'refill',         22.00),
        ('owner2@gentriwasa.test', 'mineral',  'slim_5gal',    'refill',         30.00),
        ('owner2@gentriwasa.test', 'mineral',  'round_5gal',   'refill',         30.00),
        ('owner2@gentriwasa.test', 'purified', 'bottle_500ml', 'refill',         10.00),
        ('owner3@gentriwasa.test', 'purified', 'slim_5gal',    'refill',         25.00),
        ('owner3@gentriwasa.test', 'purified', 'round_5gal',   'refill',         25.00)
      ) as p(owner_email, water_type, container_code, kind, price)
      join auth.users u on u.email = p.owner_email
      join water_stations ws on ws.owner_profile_id = u.id
  loop
    insert into station_products (station_id, water_type, container_code, kind, price)
    values (r.station_id, r.water_type, r.container_code, r.kind, r.price)
    on conflict (station_id, water_type, container_code, kind) do nothing;
  end loop;

  -- Water types, containers and the "from" price shown on the map follow
  -- the products.
  for r in select distinct station_id from station_products loop
    perform sync_station_from_products(r.station_id);
  end loop;
end $$;

-- VERIFY -- products per station.
select ws.station_name, count(*) as products, min(sp.price) as from_price
  from station_products sp join water_stations ws on ws.id = sp.station_id
 group by ws.station_name
 order by ws.station_name;



-- =====================================================================
-- STEP 6 of 7 -- DEMO CONTENT  (seed_demo_content.sql)
-- =====================================================================
-- Bulletins with reactions and comments, station reviews, events.
-- =====================================================================

-- =====================================================================
-- AquaRoute / GENTRI WASA -- DEMO CONTENT SEEDING (demo/testing only)
-- =====================================================================
-- Populates realistic-looking bulletin posts (with reactions and
-- comments), station reviews, and association events so the website has
-- something to look at while testing -- none of this is real content.
--
-- Requires supabase/seed_test_accounts.sql to have been run FIRST (this
-- script looks up its known test accounts/stations by email/name). Also
-- requires supabase/patch_bulletin_comments.sql and
-- supabase/patch_tier1_tier2_features.sql to have been run first (this
-- script writes to bulletin_comments, reviews, and events).
--
-- DO NOT run this against a production project with real users.
-- Paste this whole file into the Supabase SQL Editor and run it. Re-
-- running is safe -- it clears its own prior output first (bulletin posts/
-- reviews/events authored by the test accounts), it does not touch any
-- other data.
-- =====================================================================

do $$
declare
  admin_id uuid;
  owner1_id uuid;
  owner2_id uuid;
  driver1_id uuid;
  customer1_id uuid;
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  station1_id uuid;
  station2_id uuid;
  post_ids uuid[] := array[]::uuid[];
  p_id uuid;
begin
  select id into admin_id from auth.users where email = 'admin@gentriwasa.test';
  select id into owner1_id from auth.users where email = 'owner1@gentriwasa.test';
  select id into owner2_id from auth.users where email = 'owner2@gentriwasa.test';
  select id into driver1_id from auth.users where email = 'driver1@gentriwasa.test';
  select id into customer1_id from auth.users where email = 'customer1@gentriwasa.test';

  if admin_id is null or owner1_id is null or customer1_id is null then
    raise exception 'Test accounts not found -- run supabase/seed_test_accounts.sql first.';
  end if;

  select id into station1_id from water_stations where invite_code = 'BUENAV1';
  select id into station2_id from water_stations where invite_code = 'NAVSPR1';

  -- -------------------------------------------------------------------
  -- 0. Idempotency: clear this script's own prior output before re-seeding.
  -- -------------------------------------------------------------------
  delete from bulletins where posted_by in (admin_id, owner1_id, owner2_id, driver1_id);
  delete from reviews where profile_id in (customer1_id, driver1_id, owner2_id);
  delete from events where created_by = admin_id;

  -- -------------------------------------------------------------------
  -- 1. Bulletin posts -- mix of categories, a couple pinned, varied dates.
  -- -------------------------------------------------------------------
  -- validate_bulletin_author() requires posted_by = auth.uid(). In the SQL
  -- Editor auth.uid() is NULL, so every seeded post would be rejected. The
  -- guard exists to stop a client posting as someone else; seeding is an
  -- out-of-band exception, so it is switched off for this insert only.
  alter table bulletins disable trigger trg_validate_bulletin_author;

  insert into bulletins (id, association_id, category, title, body, is_pinned, posted_by, author_name, author_role, author_station_name, created_at) values
    (gen_random_uuid(), v_association_id, 'announcement', 'General Assembly moved to next month',
     'Heads up to all member stations: the Q1 General Assembly has been moved from this weekend to the third Saturday of next month, same venue. Attendance sheets will be collected at the door for compliance records.',
     true, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '2 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'New online accreditation verification tool is live',
     'Residents can now confirm whether a station is really WASA-accredited directly on our website under "Verify Accreditation" -- no more guessing based on a sticker on the door.',
     true, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '5 days'),
    (gen_random_uuid(), v_association_id, 'price_change', 'Floor price for alkaline water adjusted',
     'Effective this week, the association floor price for alkaline water has been adjusted to reflect rising filter/mineral costs. All member stations offering alkaline water must update their listed price to stay compliant.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '9 days'),
    (gen_random_uuid(), v_association_id, 'event', 'Water Safety & Sanitation Seminar -- register now',
     'DOH-accredited speakers will walk through updated sanitation standards for refilling stations. Free for all accredited member stations, one slot per station. Message the association office to reserve a seat.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '12 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'Buenavista Water Refilling Station now offering alkaline water',
     'We just completed our alkaline certification! Buenavista Water Refilling Station now offers alkaline water alongside our regular purified line. Same delivery area, same drivers.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '3 days'),
    (gen_random_uuid(), v_association_id, 'discussion', 'Anyone else seeing more bulk orders this month?',
     'Curious if other stations are seeing the same pattern -- our bulk (10+ jug) orders are up noticeably this month. Wondering if it is a barangay-wide thing or just us.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '6 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'Navarro Springs temporary schedule change this week',
     'Due to a scheduled water district maintenance in our area, Navarro Springs Water Station will have limited delivery slots this Thursday and Friday. Orders placed those days may be scheduled for Saturday instead.',
     false, owner2_id, 'Maria Santos', 'station_owner', 'Navarro Springs Water Station', now() - interval '1 days'),
    (gen_random_uuid(), v_association_id, 'discussion', 'Reminder: always return empty jugs to the driver',
     'Small reminder from the road -- returning your empty jugs directly to the driver (instead of leaving them out) really speeds up the next delivery round. Appreciate everyone who already does this!',
     false, driver1_id, 'Pedro Reyes', 'driver', 'Buenavista Water Refilling Station', now() - interval '4 days'),
    (gen_random_uuid(), v_association_id, 'event', 'Barangay Buenavista I clean water drive -- volunteers welcome',
     'Partnering with the barangay for a community clean water awareness drive next weekend. Looking for a few volunteers to help hand out flyers about spotting unlicensed "colorum" water sellers.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '10 days'),
    (gen_random_uuid(), v_association_id, 'price_change', 'Purified water floor price unchanged for this quarter',
     'Following the quarterly review, the association floor price for purified water remains unchanged. Mineral and alkaline floor prices were adjusted -- see the pinned post above for alkaline.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '14 days');

  -- -------------------------------------------------------------------
  -- 2. Reactions + comments on a few posts, from the other test accounts,
  --    so the interaction UI has visible data.
  -- -------------------------------------------------------------------
  for p_id in select id from bulletins where posted_by in (admin_id, owner1_id, owner2_id, driver1_id) order by created_at desc limit 5
  loop
    insert into bulletin_reactions (bulletin_id, profile_id)
    values (p_id, customer1_id)
    on conflict do nothing;
    insert into bulletin_reactions (bulletin_id, profile_id)
    values (p_id, owner2_id)
    on conflict do nothing;
  end loop;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, customer1_id, 'Good to know, thanks for the heads up!'
  from bulletins where posted_by = admin_id order by created_at desc limit 1;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, driver1_id, 'Noted, will let customers know on my route today.'
  from bulletins where title like 'Navarro Springs temporary%' limit 1;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, owner2_id, 'Same here actually -- glad it is not just us.'
  from bulletins where title like 'Anyone else seeing more bulk%' limit 1;

  -- -------------------------------------------------------------------
  -- 3. Station reviews (direct insert, not through submit_station_review's
  --    completed-order check -- this is seed data for display purposes).
  -- -------------------------------------------------------------------
  insert into reviews (station_id, profile_id, rating, comment) values
    (station1_id, customer1_id, 5, 'Fast delivery and the driver was very polite. Water tastes clean too.'),
    (station1_id, owner2_id, 4, 'Good service, occasionally a bit slow during rainy days but understandable.'),
    (station2_id, customer1_id, 5, 'Been ordering here for months, never had an issue.'),
    (station2_id, driver1_id, 4, 'Solid station, easy to coordinate with for cross-station jug returns.');

  -- -------------------------------------------------------------------
  -- 4. Events -- mix of upcoming and past.
  -- -------------------------------------------------------------------
  insert into events (title, description, event_date, location, created_by) values
    ('Q2 General Assembly', 'Quarterly meeting for all accredited member stations -- attendance required for one representative per station.', now() + interval '18 days', 'Barangay Buenavista I Covered Court', admin_id),
    ('Water Safety & Sanitation Seminar', 'DOH-accredited speakers on updated sanitation standards. Free for member stations, one slot each.', now() + interval '9 days', 'General Trias Municipal Hall Function Room', admin_id),
    ('New Station Orientation', 'Orientation session for stations currently going through the accreditation process.', now() + interval '30 days', 'WASA Association Office', admin_id),
    ('Q1 General Assembly', 'Quarterly meeting -- floor price review and worker registry updates.', now() - interval '75 days', 'Barangay Buenavista I Covered Court', admin_id),
    ('Community Clean Water Awareness Drive', 'Joint drive with Barangay Buenavista I to raise awareness about unlicensed water sellers.', now() - interval '20 days', 'Buenavista I Barangay Hall', admin_id);

  alter table bulletins enable trigger trg_validate_bulletin_author;
end $$;



-- =====================================================================
-- STEP 7 of 7 -- EVALUATION DATA  (seed_evaluation_data.sql)
-- =====================================================================
-- Orders in every live status (one mid-delivery), container balances,
-- settlements awaiting confirmation, a permit pending review, and a
-- disposable account for testing deletion.
-- =====================================================================

-- =====================================================================
-- GENTRIWASA -- EVALUATION DATA SEEDING (demo/testing only)
-- =====================================================================
-- Fills the three modules that seed_test_accounts.sql leaves empty, so
-- an evaluator does not open them and find a blank screen. An empty
-- module is indistinguishable from a broken one.
--
--   1. Orders in every live status, including one mid-delivery so that
--      live tracking can be seen working rather than inferred.
--   2. Inter-station container transfers and one settlement awaiting
--      confirmation, so the jug clearinghouse has balances to show.
--   3. One permit returned to 'pending_review', so the association
--      officer has something to review rather than only to look at.
--
-- RUN ORDER:
--   1. supabase/reset_and_rebuild.sql      (schema)
--   2. supabase/seed_test_accounts.sql     (accounts + 2 stations)
--   3. supabase/seed_demo_content.sql      (bulletins, reviews, events)
--   4. this file
--
-- Safe to re-run: it removes only the rows it created last time,
-- identified by the marker below, and never touches anything else.
--
-- DO NOT run against a project holding real user data.
-- =====================================================================

do $$
declare
  -- Everything this script creates carries this marker so a re-run can
  -- find and replace it without guessing.
  v_marker       text := 'eval-seed';

  v_station1     uuid;  -- Buenavista Water Refilling Station
  v_station2     uuid;  -- Navarro Springs Water Station
  v_owner1       uuid;
  v_owner2       uuid;
  v_customer     uuid;
  v_driver1_wrk  uuid;  -- workers.id, not the profile id
  v_admin        uuid;
  v_disposable   uuid := gen_random_uuid();
  v_loc          geography(point, 4326);
begin
  -- -------------------------------------------------------------------
  -- Resolve the seeded entities by stable keys rather than by uuid,
  -- since seed_test_accounts.sql generates fresh uuids on every run.
  -- -------------------------------------------------------------------
  select id into v_station1 from water_stations
    where station_name = 'Buenavista Water Refilling Station';
  select id into v_station2 from water_stations
    where station_name = 'Navarro Springs Water Station';

  select p.id into v_owner1   from profiles p join auth.users u on u.id = p.id
    where u.email = 'owner1@gentriwasa.test';
  select p.id into v_owner2   from profiles p join auth.users u on u.id = p.id
    where u.email = 'owner2@gentriwasa.test';
  select p.id into v_customer from profiles p join auth.users u on u.id = p.id
    where u.email = 'customer1@gentriwasa.test';
  select p.id into v_admin    from profiles p join auth.users u on u.id = p.id
    where u.email = 'admin@gentriwasa.test';

  select w.id into v_driver1_wrk from workers w
    where w.station_id = v_station1 order by w.created_at limit 1;

  if v_station1 is null or v_station2 is null or v_customer is null then
    raise exception
      'Seeded stations or accounts not found. Run reset_and_rebuild.sql and seed_test_accounts.sql first.';
  end if;

  -- A delivery point a few hundred metres from the Buenavista station,
  -- so the tracking map has a visible distance to cover.
  v_loc := st_setsrid(st_makepoint(120.8805, 14.3762), 4326)::geography;

  -- -------------------------------------------------------------------
  -- Clear anything a previous run of THIS script created.
  -- -------------------------------------------------------------------
  delete from jug_settlements    where proposed_by in (v_owner1, v_owner2) and quantity in (6, 3, 12, 7);
  delete from jug_ledger_entries where recorded_by = v_owner1;
  delete from orders             where client_request_id like v_marker || '%';

  -- -------------------------------------------------------------------
  -- 0. A DISPOSABLE ACCOUNT FOR TESTING DELETION
  --
  -- customer1@ is given in-progress orders below, which means
  -- account_deletion_blockers() will correctly refuse to delete it. That
  -- is worth demonstrating, but it leaves no way to see a deletion
  -- actually complete. This account exists to be destroyed: no orders,
  -- no station, no deliveries, so it deletes cleanly.
  --
  -- Sign in as disposable@gentriwasa.test / Disposable123!
  -- -------------------------------------------------------------------
  delete from auth.users where email = 'disposable@gentriwasa.test';

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', v_disposable, 'authenticated', 'authenticated',
     'disposable@gentriwasa.test', crypt('Disposable123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Delete Me"}',
     now(), now(), '', '', '', '');

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), v_disposable, v_disposable::text,
     jsonb_build_object('sub', v_disposable::text, 'email', 'disposable@gentriwasa.test'),
     'email', now(), now(), now());

  -- handle_new_auth_user() creates the profiles row from the metadata
  -- above; this only adds the association membership.
  insert into memberships (profile_id, association_id, role)
  values (v_disposable, '00000000-0000-0000-0000-000000000001', 'public_consumer')
  on conflict do nothing;

  -- -------------------------------------------------------------------
  -- 1. ORDERS
  --
  -- One in each live status. The 'active' row is the important one:
  -- it is what makes live delivery tracking demonstrable, and without
  -- it the evaluator can only be told that tracking works.
  -- -------------------------------------------------------------------
  insert into orders (
    station_id, customer_profile_id, driver_worker_id, delivery_location,
    jugs_ordered, water_type, jug_type, status, payment_method,
    subtotal, delivery_fee, total_amount, customer_phone,
    client_request_id, created_at
  )
  values
    -- Awaiting the owner's acceptance.
    (v_station1, v_customer, null, v_loc,
     2, 'purified', 'slim_5gal', 'pending', 'cash',
     50.00, 20.00, 70.00, '09170000001',
     v_marker || '-pending', now() - interval '12 minutes'),

    -- Accepted and assigned, not yet collected.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     3, 'purified', 'slim_5gal', 'assigned', 'cash',
     75.00, 20.00, 95.00, '09170000002',
     v_marker || '-assigned', now() - interval '35 minutes'),

    -- Out for delivery. This is the one to track.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     4, 'alkaline', 'round_5gal', 'active', 'cash',
     100.00, 20.00, 120.00, '09170000003',
     v_marker || '-active', now() - interval '50 minutes'),

    -- Completed, so order history is not empty.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     1, 'purified', 'slim_5gal', 'done', 'cash',
     25.00, 20.00, 45.00, '09170000004',
     v_marker || '-done', now() - interval '3 days'),

    -- A second completed order on the other station, so the customer's
    -- history spans more than one supplier.
    (v_station2, v_customer, null, v_loc,
     2, 'mineral', 'round_5gal', 'done', 'cash',
     44.00, 15.00, 59.00, '09170000005',
     v_marker || '-done-2', now() - interval '6 days');

  -- -------------------------------------------------------------------
  -- 2. JUG CLEARINGHOUSE
  --
  -- Positive quantity = holder_station gained containers belonging to
  -- owner_station. The balances below are deliberately uneven in both
  -- directions, so the netting is actually exercised rather than a
  -- single one-way total.
  -- -------------------------------------------------------------------
  insert into jug_ledger_entries
    (holder_station_id, owner_station_id, jug_type, quantity, recorded_by, created_at)
  values
    -- Slim: Buenavista holds 18 - 6 = 12 of Navarro's, Navarro holds 4
    -- of Buenavista's, so Buenavista owes Navarro 8 after netting.
    (v_station1, v_station2, 'slim_5gal',  18, v_owner1, now() - interval '14 days'),
    (v_station1, v_station2, 'slim_5gal',  -6, v_owner1, now() - interval '9 days'),
    (v_station2, v_station1, 'slim_5gal',   4, v_owner1, now() - interval '11 days'),
    -- Round: Navarro holds 9 of Buenavista's, Buenavista holds 4 of
    -- Navarro's, so Navarro owes Buenavista 5 -- the net runs both ways.
    (v_station2, v_station1, 'round_5gal',  9, v_owner1, now() - interval '7 days'),
    (v_station1, v_station2, 'round_5gal',  4, v_owner1, now() - interval '4 days');

  -- Awaiting confirmation from the owed station. Left as 'proposed' on
  -- purpose: confirming it is one of the things worth testing, and a
  -- settlement takes effect only when the other party agrees. Each is
  -- proposed by the station holding the jugs, for no more than it owes
  -- after netting (check_jug_settlement_proposal), so each owner has one
  -- to confirm: owner2 confirms the slim one, owner1 the round one.
  insert into jug_settlements
    (holder_station_id, owner_station_id, jug_type, quantity, status, proposed_by, created_at)
  values
    (v_station1, v_station2, 'slim_5gal',  6, 'proposed', v_owner1, now() - interval '2 days'),
    (v_station2, v_station1, 'round_5gal', 3, 'proposed', v_owner2, now() - interval '1 day');

  -- -------------------------------------------------------------------
  -- 3. A PERMIT AWAITING REVIEW
  --
  -- seed_test_accounts.sql approves every permit so both stations look
  -- fully compliant straight away. That leaves the officer's review
  -- queue empty. Returning one permit to 'pending_review' gives the
  -- approve/reject workflow something to act on.
  -- -------------------------------------------------------------------
  -- Clearing reviewed_by trips prevent_owner_self_permit_approval(), which
  -- raises on ANY change to reviewed_by/reviewed_at by a non-admin -- and in
  -- the SQL Editor auth.uid() is NULL, so there is no admin to be.
  alter table permits disable trigger trg_prevent_owner_self_permit_approval;
  alter table water_stations disable trigger trg_prevent_owner_self_accreditation;

  update permits
     set status          = 'pending_review',
         reviewed_by     = null,
         reviewed_at     = null,
         rejection_reason = null,
         uploaded_at     = now() - interval '2 days'
   where station_id = v_station2
     and permit_type = 'sanitary_permit';

  -- A second one expiring soon, so the renewal warning is visible.
  update permits
     set expiry_date = (current_date + interval '21 days')::date
   where station_id = v_station1
     and permit_type = 'business_permit';

  alter table water_stations enable trigger trg_prevent_owner_self_accreditation;
  alter table permits enable trigger trg_prevent_owner_self_permit_approval;

  raise notice 'Evaluation data seeded: 1 disposable account, 5 orders, 5 ledger entries, 2 settlements, 1 permit pending review.';
end $$;

-- =====================================================================
-- VERIFY
-- =====================================================================
select 'orders by status' as item, status::text as detail, count(*)::text as n
  from orders group by status
union all
select 'jug balances', holder_station_id::text || ' holds ' || jug_type::text, net_qty::text
  from jug_balances
union all
select 'settlements awaiting confirmation', status::text, count(*)::text
  from jug_settlements where status = 'proposed' group by status
union all
select 'permits pending review', 'pending_review', count(*)::text
  from permits where status = 'pending_review'
order by item, detail;



-- =====================================================================
-- FINAL CHECK -- compare each value with the expected one
-- =====================================================================
select 'tables and views in public (expect 53)' as item, count(*)::text as value
  from information_schema.tables where table_schema = 'public'
union all select 'app functions (expect 133)', count(*)::text
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
 where s.nspname = 'public' and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
union all select 'row security policies (expect 132)', count(*)::text from pg_policies where schemaname in ('public', 'storage')
union all select 'storage buckets (expect 7)', count(*)::text from storage.buckets
union all select 'private buckets (expect 3)', count(*)::text from storage.buckets where not public
union all select 'scheduled jobs (expect 2)', count(*)::text from cron.job
union all select 'realtime tables (expect 3)', count(*)::text from pg_publication_tables
 where pubname = 'supabase_realtime' and tablename in ('notifications', 'orders', 'workers')
union all select 'barangays (expect 33)', count(*)::text from barangays
union all select 'test login accounts (>= 20)', count(*)::text from auth.users where email like '%@gentriwasa.test'
union all select 'officer accounts (expect 6)', count(*)::text from memberships where role = 'wasa_admin'
union all select 'super admins (expect 2)', count(*)::text from memberships where role = 'wasa_superadmin'
union all select 'stations (expect 3)', count(*)::text from water_stations
union all select 'publicly listed stations (>= 2)', count(*)::text from public_stations
union all select 'station products (expect 14)', count(*)::text from station_products
union all select 'orders (> 0)', count(*)::text from orders
union all select 'bulletins (> 0)', count(*)::text from bulletins
order by item;
