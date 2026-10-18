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

-- ---------------------------------------------------------------------
-- VERIFY
-- ---------------------------------------------------------------------
select check_name, ok from (values
  ('order channel column', exists (select 1 from information_schema.columns where table_name = 'orders' and column_name = 'order_channel')),
  ('station_create_order', exists (select 1 from pg_proc where proname = 'station_create_order')),
  ('mentor column', exists (select 1 from information_schema.columns where table_name = 'water_stations' and column_name = 'mentor_station_id')),
  ('mentor guard', exists (select 1 from pg_trigger where tgname = 'trg_guard_mentor_change')),
  ('cost profiles owner-only', (select count(*) from pg_policies where tablename = 'station_cost_profiles') = 1),
  ('dispute columns', exists (select 1 from information_schema.columns where table_name = 'jug_settlements' and column_name = 'disputed_at')),
  ('event rsvps', exists (select 1 from information_schema.tables where table_name = 'event_rsvps'))
) as v(check_name, ok);
