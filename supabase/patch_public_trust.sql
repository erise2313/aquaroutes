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
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when ok then 'ok' else 'NOT APPLIED' end as result from (values
  ('public station facts', exists (select 1 from information_schema.columns where table_name = 'public_stations' and column_name = 'last_water_test_at')),
  ('reports table', exists (select 1 from information_schema.tables where table_name = 'station_reports')),
  ('reports bucket private', exists (select 1 from storage.buckets where id = 'station-reports' and not public)),
  ('admin_list_orders', exists (select 1 from pg_proc where proname = 'admin_list_orders')),
  ('officer direct order read closed', exists (select 1 from pg_policies where policyname = 'orders_admin_read' and qual = 'false')),
  ('safe-water articles', (select count(*) from web_content_items where page_key = 'safe_water') >= 4)
) as t(item, ok);
