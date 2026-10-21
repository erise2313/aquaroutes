-- GENTRI WASA setup -- PART 4 of 5. Run the parts in order,
-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)

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

-- station_names(): order lists show station names to customers, who cannot
-- read water_stations rows (they hold invite and staff codes).
create or replace function station_names(p_ids uuid[])
returns table (id uuid, station_name text)
language sql stable security definer set search_path = public
as $$
  select ws.id, ws.station_name from water_stations ws where ws.id = any(p_ids);
$$;

grant execute on function station_names(uuid[]) to authenticated;

-- order_customer_contact(): the customer's name and phone for one order.
--
-- The driver dashboard read these through a profiles(...) embed, but drivers
-- can't read other people's profiles, so every delivery said "Deliver to:
-- Water Customer" with no number to call. This returns the two fields only,
-- and only to the driver assigned to the order while it is being delivered,
-- or to that station's owner or staff. Officers are not included: customer
-- identity on orders stays hidden from them unless a report is linked
-- (admin_list_orders handles that case).
create or replace function order_customer_contact(p_order_id uuid)
returns table (full_name text, phone_number text)
language sql stable security definer set search_path = public
as $$
  select coalesce(p.full_name, o.guest_name),
         coalesce(nullif(o.customer_phone, ''), p.phone_number, o.guest_phone)
  from orders o
  left join profiles p on p.id = o.customer_profile_id
  where o.id = p_order_id
    and (
      (o.status in ('assigned', 'active')
        and exists (select 1 from workers w where w.id = o.driver_worker_id and w.profile_id = auth.uid()))
      or exists (select 1 from water_stations ws where ws.id = o.station_id and ws.owner_profile_id = auth.uid())
      or o.station_id = auth_staff_station_id()
    );
$$;

revoke all on function order_customer_contact(uuid) from public, anon;
grant execute on function order_customer_contact(uuid) to authenticated;

-- VERIFY: select * from order_customer_contact('<order id>');  -- as the assigned driver

-- Every station always has a staff code, and each join path says plainly
-- when someone typed the other kind of code.
--
-- Staff codes only existed once an owner pressed "Create a staff code" on
-- Team, which nobody had done, so the only code anyone saw was the drivers'
-- one on the dashboard. Staff registering with it were refused with
-- "Invalid staff code". The two codes stay separate on purpose: a driver
-- code must not make someone staff (staff see the station's orders and
-- customer contacts).

-- 1. New stations get a staff code when they are created.
create or replace function fill_staff_invite_code()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.staff_invite_code is null then
    new.staff_invite_code := new_invite_code();
  end if;
  return new;
end;
$$;

create or replace trigger trg_fill_staff_invite_code
  before insert on water_stations
  for each row execute function fill_staff_invite_code();

-- 2. Existing stations. The three test stations get readable codes for the
-- test accounts sheet; the rest get random ones. No expiry, like the
-- stations' existing driver codes; issuing a new one from Team sets the
-- association's validity period.
update water_stations set staff_invite_code = 'STAFFBV'
  where invite_code = 'BUENAV1' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFBV');
update water_stations set staff_invite_code = 'STAFFNV'
  where station_name = 'Navarro Springs Water Station' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFNV');
update water_stations set staff_invite_code = 'STAFFTJ'
  where invite_code = 'TEJERO1' and staff_invite_code is null
    and not exists (select 1 from water_stations where staff_invite_code = 'STAFFTJ');
update water_stations set staff_invite_code = new_invite_code()
  where staff_invite_code is null;

-- 3. Staff who type the driver code are told which code they need.
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
    from water_stations where staff_invite_code ilike trim(p_staff_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where invite_code ilike trim(p_staff_code)) then
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

-- 4. Drivers who type the staff code are told the same, the other way round.
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
    from water_stations where invite_code ilike trim(p_invite_code);
  if v_station_id is null then
    if exists (select 1 from water_stations where staff_invite_code ilike trim(p_invite_code)) then
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

-- VERIFY: select station_name, invite_code, staff_invite_code from water_stations order by 1;

-- Invite and staff codes match the way people type them.
--
-- Codes were matched exactly apart from letter case, so a driver who typed
-- the letter O for a zero ("6C8OLK" for 6C80LK), I for a one, or a space
-- was told the code was invalid. Older stations' codes were made by the app
-- with all 36 characters, so these look-alikes occur. Both sides are now
-- compared in a normal form: no spaces, upper case, O read as 0, I as 1.

create or replace function invite_code_key(p_code text)
returns text
language sql immutable
as $$
  select translate(upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g')), 'OI', '01');
$$;

create or replace function driver_switch_station(p_invite_code text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
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
    from water_stations where invite_code_key(invite_code) = invite_code_key(p_invite_code);
  if v_new_station_id is null then
    if exists (select 1 from water_stations where invite_code_key(staff_invite_code) = invite_code_key(p_invite_code)) then
      raise exception 'That is the station''s staff code. Drivers need the station''s driver invite code from the owner''s dashboard.';
    end if;
    raise exception 'Invalid station invite code.';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'This invite code has expired. Ask the station for a new one.';
  end if;

  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');
  perform set_config('gentri.trusted_order_change', 'off', true);
  update workers set station_id = v_new_station_id, updated_at = now() where id = v_worker_id;
  update memberships set station_id = v_new_station_id, association_id = v_association_id
    where profile_id = auth.uid() and role = 'driver';
  insert into worker_station_history (worker_id, station_id) values (v_worker_id, v_new_station_id);
end;
$function$;
