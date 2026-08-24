-- =====================================================================
-- Tier 1 + Tier 2 feature patch: scheduled delivery, live driver tracking
-- + contact info, station reviews, downloadable resources, events.
-- Additive/corrective -- no data loss. Paste into the Supabase SQL Editor
-- and run once. Safe to re-run.
-- =====================================================================

-- ---- Item 4: ASAP vs. Scheduled delivery ----

alter table orders add column if not exists scheduled_for timestamptz;

drop function if exists insert_quick_order(uuid, double precision, double precision, int, text, numeric, numeric, numeric, text, text, text);

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
  p_scheduled_for timestamptz default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select is_active into v_is_active from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active then
    raise exception 'This station is not currently accepting orders.';
  end if;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type,
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id, p_scheduled_for
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- Items 3 & 7: driver contact + live location for the customer's own active order ----
-- Security-definer RPC, not RLS -- guest orders have no auth.uid() to scope a
-- policy against, so authorization happens inside the function for both
-- guest (phone match) and authenticated (customer_profile_id match) callers.

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

-- ---- Item 8: station ratings/reviews ----

create table if not exists reviews (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (station_id, profile_id)
);

create index if not exists reviews_station_idx on reviews (station_id);

alter table reviews enable row level security;

drop policy if exists reviews_public_read on reviews;
create policy reviews_public_read on reviews for select
  using (true);

drop policy if exists reviews_admin_all on reviews;
create policy reviews_admin_all on reviews for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

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

drop view if exists public_stations cascade;

create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, b.name as barangay_name,
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

-- ---- Item 9: downloadable resources library ----

create table if not exists resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'general',
  storage_path text not null,
  file_url text not null,
  uploaded_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

alter table resources enable row level security;

drop policy if exists resources_public_read on resources;
create policy resources_public_read on resources for select
  using (true);

drop policy if exists resources_admin_all on resources;
create policy resources_admin_all on resources for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

insert into storage.buckets (id, name, public)
  values ('resources', 'resources', true)
  on conflict (id) do nothing;

drop policy if exists resources_admin_write on storage.objects;
create policy resources_admin_write on storage.objects for all
  using (bucket_id = 'resources' and auth_has_role('wasa_admin'))
  with check (bucket_id = 'resources' and auth_has_role('wasa_admin'));

-- ---- Item 10: events calendar ----

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_date timestamptz not null,
  location text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists events_event_date_idx on events (event_date);

alter table events enable row level security;

drop policy if exists events_public_read on events;
create policy events_public_read on events for select
  using (true);

drop policy if exists events_admin_all on events;
create policy events_admin_all on events for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));
