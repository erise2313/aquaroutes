-- GENTRI WASA setup -- PART 2 of 5. Run the parts in order,
-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)

insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('for_station_owners', 'requirements_summary', 'Business Permit, Sanitary Permit, FDA License to Operate, a Fire Safety Inspection Certificate, a Water Quality Test Report, and an Operator Training Certificate at minimum -- plus additional certifications if you offer alkaline water or source your own well water.', 0)
on conflict do nothing;

-- ---- Seed: How Accreditation Works -- process steps ----
insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('how_accreditation_works', 'steps', 'Register the station', 'The owner creates an account and registers their station with basic details (name, address, offered water types).', 0),
  ('how_accreditation_works', 'steps', 'Upload required documents', 'Every station uploads its Business Permit, Sanitary Permit, FDA License, Fire Safety Inspection Certificate, Water Quality Test Report, and Operator Training Certificate. Stations offering alkaline water also upload two additional certifications, and WASA may require the NWRB Water Permit/Certificate of Public Convenience for stations sourcing their own well water.', 1),
  ('how_accreditation_works', 'steps', 'WASA reviews each document', 'A WASA admin reviews every uploaded document individually -- approving, or rejecting with a stated reason so the owner knows exactly what to fix.', 2),
  ('how_accreditation_works', 'steps', 'Accreditation is automatic once complete', 'The moment every required document is approved, the station is automatically marked accredited -- no separate manual step, and no way for a station to grant itself accreditation.', 3),
  ('how_accreditation_works', 'steps', 'The colorum-verification seal appears', 'Accredited, WASA-verified stations get the verification seal on the public station directory, so residents can tell a legitimate operator from an unlicensed one at a glance.', 4)
on conflict do nothing;

-- ---- Seed: Jug Clearinghouse Explainer ----
-- Step 1's copy is corrected here (not just copied verbatim) -- it used
-- to describe the old fully-manual recording flow; patch_jug_provenance.sql
-- made this automatic at delivery completion, so the explainer should
-- say that, not the outdated mechanism.
insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('jug_clearinghouse', 'intro', 'Reusable Slim and Round 5-gallon jugs regularly end up at a different station than the one that owns them -- a driver delivers water in one station''s jug, and picks up an empty jug bearing a competitor''s brand. Without a shared system, that jug is effectively lost to its owner. The clearinghouse makes those swaps fair and auditable across the whole association.', 0)
on conflict do nothing;

insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('jug_clearinghouse', 'steps', 'A jug crosses station lines', 'When a customer exchanges an empty jug at a different station than the one that owns it, the app automatically records who now holds the jug and who it belongs to as soon as the delivery is completed.', 0),
  ('jug_clearinghouse', 'steps', 'The ledger tracks who holds what', 'Every cross-station transfer is logged as a ledger entry -- which station now holds the jug, and which station originally owns it.', 1),
  ('jug_clearinghouse', 'steps', 'Balances net out automatically', 'Instead of settling jug-by-jug, the system nets all transfers between two stations into a single running balance per jug type.', 2),
  ('jug_clearinghouse', 'steps', 'Stations propose and confirm settlement', 'A holder station proposes a settlement to clear its balance; the owner station confirms or rejects it. Confirming atomically posts the offsetting ledger entry, so the balance can''t drift or be double-counted.', 3)
on conflict do nothing;

-- ---- Seed: permit type labels (all 10 known values) ----
insert into permit_type_labels (permit_type, label, condition_note, sort_order) values
  ('business_permit', 'Mayor''s Business Permit', 'Required for every station.', 0),
  ('sanitary_permit', 'Sanitary Permit', 'Required for every station.', 1),
  ('fda_license', 'FDA License to Operate', 'Required for every station.', 2),
  ('fire_safety_certificate', 'Fire Safety Inspection Certificate (BFP)', 'Required for every station.', 3),
  ('water_quality_test_report', 'Water Quality Test Report (DOH)', 'Required for every station.', 4),
  ('operator_training_certificate', 'Operator Training Certificate (CCWRSPO)', 'Required for every station.', 5),
  ('alkaline_tech_cert', 'Alkaline Machine Technical Certification', 'Only required if the station offers alkaline water.', 6),
  ('alkaline_water_test', 'Alkaline Water Quality Test Report', 'Only required if the station offers alkaline water.', 7),
  ('nwrb_water_permit', 'NWRB Water Permit', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 8),
  ('nwrb_certificate_of_public_convenience', 'NWRB Certificate of Public Convenience', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 9)
on conflict (permit_type) do nothing;


-- ---------------------------------------------------------------------
-- supabase/patch_accredited_at.sql  (live migration 20260908111123)
-- ---------------------------------------------------------------------
-- Records WHEN a station became accredited, so the admin dashboard can chart
-- accreditations over time.
--
-- Why this is needed: water_stations has created_at (registered),
-- updated_at (last edited, for any reason) and accreditation_override_at
-- (manual certification only). None of them answers "when did this station
-- become accredited". Charting updated_at would silently mislabel "someone
-- edited the phone number" as "accredited this month".
--
-- Why a trigger rather than editing the functions that grant accreditation:
-- is_accredited is written from two places -- recompute_accreditation()
-- (patch_admin_accreditation_override.sql) when a permit changes, and
-- set_accreditation_override() when an admin manually certifies. A BEFORE
-- UPDATE trigger on the transition catches both, plus any future path,
-- without touching either function's logic.
--
-- Historical rows stay null on purpose: there is no honest way to backfill a
-- date that was never recorded, so the dashboard labels its earliest bucket
-- rather than inventing history. Idempotent -- safe to run more than once.

alter table water_stations add column if not exists accredited_at timestamptz;

comment on column water_stations.accredited_at is
  'When is_accredited last became true. Null for stations accredited before this column existed, and cleared if accreditation is lost.';

create or replace function stamp_accredited_at() returns trigger as $$
begin
  if new.is_accredited and not coalesce(old.is_accredited, false) then
    -- false -> true: this is the moment of accreditation.
    new.accredited_at := now();
  elsif not new.is_accredited then
    -- Lost (or never had) accreditation. Clearing means a station that is
    -- re-accredited later gets the new date rather than a stale first one,
    -- which is what "accredited this quarter" should count.
    new.accredited_at := null;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at on water_stations;
create trigger trg_stamp_accredited_at
  before update on water_stations
  for each row
  when (old.is_accredited is distinct from new.is_accredited)
  execute function stamp_accredited_at();

-- A station inserted already accredited would otherwise never fire the
-- update trigger.
create or replace function stamp_accredited_at_insert() returns trigger as $$
begin
  if new.is_accredited then
    new.accredited_at := coalesce(new.accredited_at, now());
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at_insert on water_stations;
create trigger trg_stamp_accredited_at_insert
  before insert on water_stations
  for each row
  execute function stamp_accredited_at_insert();

create index if not exists water_stations_accredited_at_idx
  on water_stations (accredited_at)
  where accredited_at is not null;


-- ---------------------------------------------------------------------
-- supabase/patch_admin_activity_view.sql  (live migration 20260908114008 + 20260908114423 (actor_name))
-- ---------------------------------------------------------------------
-- Read-only "who did what" feed for the WASA admin portal.
--
-- Every admin mutation in this schema already stamps an actor and a
-- timestamp -- permits.reviewed_by/at, worker_incidents.resolved_by/at,
-- worker_credentials.reviewed_by/at, water_stations.accreditation_override_
-- by/at, and updated_by/at on all four CMS tables. Until now exactly one of
-- those was ever read back (permit_review_screen.dart renders "manually
-- certified by X"), so an admin could not answer "who suspended this
-- account?" or "what did I approve last week?"
--
-- This is a view, not a new audit table: the data is already being written,
-- so logging it a second time would add a write path that could disagree
-- with the records it is supposed to describe. The trade-off is that it only
-- shows the LATEST action per row -- re-reviewing a permit overwrites
-- reviewed_at, so this is an activity feed, not a full history. A real
-- append-only audit log would be a separate change.
--
-- security_invoker = on so the querying user's own RLS applies: admins
-- already have read access to every underlying table and nobody else does,
-- so this view cannot become a way around those policies.

create or replace view admin_activity
with (security_invoker = on) as
select a.actor_id, a.occurred_at, a.category, a.action, a.subject,
       coalesce(pr.full_name, 'Unknown') as actor_name
from (
  select
    p.reviewed_by                              as actor_id,
    p.reviewed_at                              as occurred_at,
    'Permit'                                   as category,
    case p.status::text
      when 'approved' then 'Approved permit'
      when 'rejected' then 'Rejected permit'
      else 'Reviewed permit'
    end                                        as action,
    coalesce(ws.station_name, 'Unknown station') || ' - ' || p.permit_type::text as subject
  from permits p
  left join water_stations ws on ws.id = p.station_id
  where p.reviewed_by is not null and p.reviewed_at is not null

  union all

  select
    wi.resolved_by,
    wi.resolved_at,
    'Worker incident',
    case wi.status::text
      when 'confirmed_flag' then 'Confirmed flag on'
      when 'dismissed' then 'Dismissed incident for'
      else 'Resolved incident for'
    end,
    coalesce(w.full_name, 'Unknown worker')
  from worker_incidents wi
  left join workers w on w.id = wi.worker_id
  where wi.resolved_by is not null and wi.resolved_at is not null

  union all

  select
    wc.reviewed_by,
    wc.reviewed_at,
    'Worker credential',
    case wc.status::text
      when 'approved' then 'Approved credential for'
      when 'rejected' then 'Rejected credential for'
      else 'Reviewed credential for'
    end,
    coalesce(w.full_name, 'Unknown worker') || ' (' || wc.credential_type::text || ')'
  from worker_credentials wc
  left join workers w on w.id = wc.worker_id
  where wc.reviewed_by is not null and wc.reviewed_at is not null

  union all

  select
    ws.accreditation_override_by,
    ws.accreditation_override_at,
    'Accreditation',
    'Manually certified',
    ws.station_name
  from water_stations ws
  where ws.accreditation_override_by is not null and ws.accreditation_override_at is not null

  union all

  select s.updated_by, s.updated_at, 'Website content', 'Edited section', s.page_key || ' / ' || s.section_key
  from web_page_sections s
  where s.updated_by is not null

  union all

  select i.updated_by, i.updated_at, 'Website content', 'Edited item', i.page_key || ' / ' || i.item_key
  from web_content_items i
  where i.updated_by is not null

  union all

  select f.updated_by, f.updated_at, 'Website content', 'Edited FAQ', f.question
  from web_faq_entries f
  where f.updated_by is not null

  union all

  select l.updated_by, l.updated_at, 'Website content', 'Edited permit label', l.permit_type::text
  from permit_type_labels l
  where l.updated_by is not null
) a
left join profiles pr on pr.id = a.actor_id;

comment on view admin_activity is
  'Latest recorded admin action per row, unioned from the actor columns the app already writes. Activity feed, not an append-only audit log.';


-- ---------------------------------------------------------------------
-- supabase/patch_server_side_pricing.sql  (live migration 20260910204546)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Server-side order pricing (Phase 1 of the product-catalog work).
--
-- Before this patch, insert_quick_order stored p_subtotal, p_delivery_fee
-- and p_total_amount exactly as the phone sent them. It runs SECURITY
-- DEFINER and is executable by anon, so anyone -- no sign-in needed --
-- could place an order at any price they liked; the driver would then
-- collect whatever the order said. Quantity, water type and container were
-- not validated either. (There were no orders in the live database when
-- this was found, so nothing had been exploited.)
--
-- This patch:
--   1. Drops two stale overloads left behind by earlier patches.
--   2. Makes the server the only thing that decides what an order costs.
--      The money parameters are kept purely so existing callers -- the
--      current app and already-installed test APKs -- keep resolving to
--      this function unchanged. Their values are ignored.
--   3. Stops the floor-price trigger firing when nothing it checks changed.
--      It was declared "UPDATE OF price_per_jug, offered_water_types",
--      which fires whenever those columns are in the SET list -- and the
--      station profile screen always sends offered_water_types -- so any
--      profile save by a station priced under a floor failed, even a name
--      change.
--   4. Clears the test floor prices (purified 100 / mineral 380 /
--      alkaline 55) until the association sets real ones.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Stale overloads. The app always calls with all 14 named parameters
--    (lib/services/order_service.dart), which resolves to the version
--    replaced below; these two only existed as leftovers, and both skip
--    the jug-exchange validation the current version does.
-- ---------------------------------------------------------------------
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz);
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz, text);

-- ---------------------------------------------------------------------
-- 2. Server-computed money. Same argument list as before, so this is a
--    true replacement rather than a new overload.
-- ---------------------------------------------------------------------
create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,        -- IGNORED: kept for caller compatibility
  p_delivery_fee numeric,    -- IGNORED: kept for caller compatibility
  p_total_amount numeric,    -- IGNORED: kept for caller compatibility
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  s water_stations%rowtype;
  v_origin uuid;
  v_subtotal numeric(10,2);
  -- Default ceiling per order; for the association to confirm.
  v_max_jugs constant integer := 50;
begin
  -- Idempotent replay: a retried request returns the order it already made.
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select * into s from water_stations where id = p_station_id;

  -- Same visibility rule as the public_stations view: a station customers
  -- can't see must not be orderable by calling this function directly.
  if not found or not s.is_active or not s.is_colorum_verified then
    raise exception 'This station is not available for ordering.';
  end if;
  if not coalesce(s.accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;

  if p_jugs_ordered is null or p_jugs_ordered < 1 or p_jugs_ordered > v_max_jugs then
    raise exception 'Please order between 1 and % jugs.', v_max_jugs;
  end if;
  if p_water_type is null or not (p_water_type = any(s.offered_water_types)) then
    raise exception 'This station does not offer % water.', coalesce(p_water_type, 'that');
  end if;
  -- A station that declares containers must be ordered in one of them.
  if cardinality(coalesce(s.offered_jug_types::text[], '{}')) > 0
     and (p_jug_type is null or not (p_jug_type = any(s.offered_jug_types::text[]))) then
    raise exception 'This station does not offer that container.';
  end if;
  if s.price_per_jug is null or s.price_per_jug <= 0 then
    raise exception 'This station has not set its prices yet.';
  end if;

  v_subtotal := p_jugs_ordered * s.price_per_jug;

  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(s.offers_jug_exchange, false)
    then p_jug_exchange_origin_station_id
    else null
  end;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for,
    jug_exchange_origin_station_id
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p_water_type, p_jug_type,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 3. Floor-price check only when something it checks actually changed.
--    Done in the function rather than a trigger WHEN clause, because a
--    trigger covering INSERT can't reference OLD.
-- ---------------------------------------------------------------------
create or replace function enforce_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
begin
  if tg_op = 'UPDATE'
     and new.price_per_jug is not distinct from old.price_per_jug
     and new.offered_water_types is not distinct from old.offered_water_types then
    return new;
  end if;

  select max(min_price_per_jug) into v_floor
    from floor_prices
    where association_id = new.association_id
      and water_type = any(new.offered_water_types);

  if v_floor is not null and new.price_per_jug < v_floor then
    raise exception 'price_per_jug (%) is below the association floor price (%) for one or more offered water types.', new.price_per_jug, v_floor;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 4. Test floor prices out until the association sets real ones.
-- ---------------------------------------------------------------------
delete from floor_prices;

-- ---------------------------------------------------------------------
-- supabase/patch_permit_sync_fix.sql  (live migration 20260910225037)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a station owner with approved alkaline permits could not save their
-- station profile at all -- not even a name change.
--
-- Two triggers combined:
--   * trg_sync_required_permits fires AFTER UPDATE OF offered_water_types,
--     i.e. whenever that column is in the SET list -- and the profile screen
--     always sends it. It then re-upserted the alkaline permits with
--     DO UPDATE SET is_required = true even when they already were.
--   * That no-op UPDATE of an approved permit tripped
--     prevent_owner_self_permit_approval, which raised whenever a non-admin
--     updated a permit whose new.status = 'approved' -- whether or not
--     anything was being approved.
--
-- Found when the product-catalog migration (which updates stations' water
-- types) failed on Buenavista, whose alkaline permits are approved.
--
-- 1. An approval is a status CHANGE to approved, not "the row is approved".
-- 2. The permit sync does nothing when the water types didn't change, and
--    never rewrites a permit whose is_required already has the target value.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if (new.status = 'approved' and new.status is distinct from old.status)
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function sync_required_permits() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    if new.offered_water_types is not distinct from old.offered_water_types then
      return new;
    end if;
  end if;

  insert into permits (station_id, permit_type, is_required)
    values
      (new.id, 'business_permit', true),
      (new.id, 'sanitary_permit', true),
      (new.id, 'fda_license', true),
      (new.id, 'fire_safety_certificate', true),
      (new.id, 'nwrb_water_permit', true),
      (new.id, 'nwrb_certificate_of_public_convenience', true),
      (new.id, 'water_quality_test_report', true),
      (new.id, 'operator_training_certificate', true)
    on conflict (station_id, permit_type) do nothing;

  if 'alkaline' = any(new.offered_water_types) then
    insert into permits (station_id, permit_type, is_required)
      values
        (new.id, 'alkaline_tech_cert', true),
        (new.id, 'alkaline_water_test', true)
      on conflict (station_id, permit_type) do update set is_required = true
        where permits.is_required is distinct from true;
  else
    update permits set is_required = false
      where station_id = new.id
        and permit_type in ('alkaline_tech_cert', 'alkaline_water_test')
        and is_required;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- supabase/patch_product_catalog.sql  (live migration 20260910225241)
-- ---------------------------------------------------------------------
-- =====================================================================
-- Per-station product catalog (Phase 2 of the pricing work).
--
-- Replaces "one price for everything" with products a station actually
-- sells: water type x container x (refill | new container), each with its
-- own price. Container sizes become a list the association manages.
-- Order prices keep coming from the server (patch_server_side_pricing.sql);
-- they now come from the product instead of a single station price.
--
-- Compatibility is deliberate throughout:
--   * water_stations.offered_water_types / offered_jug_types / price_per_jug
--     are kept, but DERIVED from available products by trigger. Every
--     existing reader -- public_stations, the directory filters, the jug
--     exchange, sync_required_permits (alkaline permits) -- keeps working,
--     and price_per_jug becomes the "from" price shown in listings.
--   * insert_quick_order still accepts the old call shape (water type +
--     container, no product id), resolving the refill product itself, so
--     app builds already installed on test phones keep ordering correctly.
--   * The two 5-gallon container codes reuse the jug-ledger enum strings,
--     so orders.jug_type and the clearinghouse keep working untouched.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Helpers. water_stations has no public SELECT policy (the public reads
--    it through the public_stations view), so an RLS policy that queries
--    water_stations directly sees nothing for an anonymous visitor. These
--    run as definer and answer one yes/no question each.
-- ---------------------------------------------------------------------
create or replace function catalog_station_is_public(p_station_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from water_stations
    where id = p_station_id and is_colorum_verified and is_active
  );
$$;

create or replace function catalog_caller_owns_station(p_station_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from water_stations
    where id = p_station_id and owner_profile_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------
-- 1. Containers the association recognises.
-- ---------------------------------------------------------------------
create table if not exists container_types (
  code text primary key,
  label text not null,
  volume_ml integer not null check (volume_ml > 0),
  is_returnable boolean not null default false,
  -- Only containers the jug clearinghouse tracks map to its enum.
  ledger_jug_type jug_type,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint container_types_ledger_requires_returnable
    check (ledger_jug_type is null or is_returnable)
);

insert into container_types (code, label, volume_ml, is_returnable, ledger_jug_type, sort_order) values
  ('slim_5gal',    'Slim 5-gal',    18927, true,  'slim_5gal',  10),
  ('round_5gal',   'Round 5-gal',   18927, true,  'round_5gal', 20),
  ('gallon_1',     '1-gallon',       3785, false, null,         30),
  ('bottle_500ml', '500 mL bottle',   500, false, null,         40),
  ('bottle_350ml', '350 mL bottle',   350, false, null,         50)
on conflict (code) do nothing;

alter table container_types enable row level security;
drop policy if exists container_types_public_read on container_types;
create policy container_types_public_read on container_types for select using (true);
drop policy if exists container_types_admin_write on container_types;
create policy container_types_admin_write on container_types for all
  using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- 2. What each station sells, at what price.
-- ---------------------------------------------------------------------
create table if not exists station_products (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  water_type text not null check (water_type in ('purified', 'mineral', 'alkaline', 'distilled')),
  container_code text not null references container_types(code),
  kind text not null default 'refill' check (kind in ('refill', 'new_container')),
  price numeric(10,2) not null check (price > 0),
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (station_id, water_type, container_code, kind)
);
create index if not exists station_products_station_idx on station_products (station_id);

alter table station_products enable row level security;
drop policy if exists station_products_public_read on station_products;
create policy station_products_public_read on station_products for select
  using (catalog_station_is_public(station_id));
drop policy if exists station_products_owner_all on station_products;
create policy station_products_owner_all on station_products for all
  using (auth_has_role('station_owner') and catalog_caller_owns_station(station_id))
  with check (auth_has_role('station_owner') and catalog_caller_owns_station(station_id));
drop policy if exists station_products_admin_all on station_products;
create policy station_products_admin_all on station_products for all
  using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

create or replace function station_products_touch_updated_at() returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;
drop trigger if exists trg_station_products_touch_updated_at on station_products;
create trigger trg_station_products_touch_updated_at
  before update on station_products
  for each row execute function station_products_touch_updated_at();

-- ---------------------------------------------------------------------
-- 3. Floor prices become water type x container, applied to refills.
--    The table is empty (the previous patch cleared the test values), so
--    the container can be required outright. Any row without one can't be
--    interpreted under the new rule and is removed.
-- ---------------------------------------------------------------------
alter table floor_prices add column if not exists container_code text references container_types(code);
delete from floor_prices where container_code is null;
alter table floor_prices alter column container_code set not null;
alter table floor_prices drop constraint if exists floor_prices_association_id_water_type_key;
alter table floor_prices drop constraint if exists floor_prices_association_water_container_key;
alter table floor_prices add constraint floor_prices_association_water_container_key
  unique (association_id, water_type, container_code);

create or replace function enforce_product_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
  v_label text;
begin
  if new.kind <> 'refill' then
    return new;  -- floors regulate refills; a new container's price includes the container
  end if;
  -- Only when something the floor depends on changed -- the same trap the
  -- station-level trigger fell into (see patch_server_side_pricing.sql).
  if tg_op = 'UPDATE'
     and new.price is not distinct from old.price
     and new.water_type is not distinct from old.water_type
     and new.container_code is not distinct from old.container_code
     and new.kind is not distinct from old.kind then
    return new;
  end if;

  select fp.min_price_per_jug into v_floor
    from floor_prices fp
    join water_stations ws on ws.association_id = fp.association_id
    where ws.id = new.station_id
      and fp.water_type = new.water_type
      and fp.container_code = new.container_code;

  if v_floor is not null and new.price < v_floor then
    select label into v_label from container_types where code = new.container_code;
    raise exception '% % refills must be at least ₱% (the association''s floor price).',
      initcap(new.water_type), coalesce(v_label, new.container_code), v_floor;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_enforce_product_floor_price on station_products;
create trigger trg_enforce_product_floor_price
  before insert or update on station_products
  for each row execute function enforce_product_floor_price();

-- The single-price station floor no longer applies.
drop trigger if exists trg_enforce_floor_price on water_stations;
drop function if exists enforce_floor_price();

-- ---------------------------------------------------------------------
-- 4. Derived station columns, kept in step with available products.
-- ---------------------------------------------------------------------
create or replace function sync_station_from_products(p_station_id uuid) returns void as $$
begin
  update water_stations ws set
    offered_water_types = coalesce((
      select array_agg(distinct sp.water_type order by sp.water_type)
      from station_products sp
      where sp.station_id = p_station_id and sp.is_available
    ), '{}'),
    -- Only containers the jug ledger tracks belong in this enum array.
    offered_jug_types = coalesce((
      select array_agg(distinct ct.ledger_jug_type order by ct.ledger_jug_type)
      from station_products sp
      join container_types ct on ct.code = sp.container_code
      where sp.station_id = p_station_id and sp.is_available and ct.ledger_jug_type is not null
    ), '{}'),
    -- "From" price for listings: cheapest returnable refill (the 5-gallon
    -- price people compare), else cheapest product, else 0.
    price_per_jug = coalesce(
      (select min(sp.price) from station_products sp
         join container_types ct on ct.code = sp.container_code
        where sp.station_id = p_station_id and sp.is_available
          and sp.kind = 'refill' and ct.is_returnable),
      (select min(sp.price) from station_products sp
        where sp.station_id = p_station_id and sp.is_available),
      0)
  where ws.id = p_station_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function station_products_sync_station() returns trigger as $$
begin
  if tg_op = 'DELETE' then
    perform sync_station_from_products(old.station_id);
  else
    perform sync_station_from_products(new.station_id);
    if tg_op = 'UPDATE' and old.station_id is distinct from new.station_id then
      perform sync_station_from_products(old.station_id);
    end if;
  end if;
  return null;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_station_products_sync_station on station_products;
create trigger trg_station_products_sync_station
  after insert or update or delete on station_products
  for each row execute function station_products_sync_station();

-- Editing a container (e.g. retiring it, or changing what the ledger
-- tracks) changes what every station selling it should advertise.
create or replace function container_types_sync_stations() returns trigger as $$
declare
  r record;
begin
  for r in select distinct station_id from station_products where container_code = new.code loop
    perform sync_station_from_products(r.station_id);
  end loop;
  return null;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_container_types_sync_stations on container_types;
create trigger trg_container_types_sync_stations
  after update on container_types
  for each row execute function container_types_sync_stations();

-- ---------------------------------------------------------------------
-- 5. Orders remember exactly what was bought and for how much, so a later
--    price change never rewrites a past order.
-- ---------------------------------------------------------------------
alter table orders add column if not exists product_id uuid references station_products(id) on delete set null;
alter table orders add column if not exists unit_price numeric(10,2);
alter table orders add column if not exists product_kind text
  check (product_kind in ('refill', 'new_container'));

-- ---------------------------------------------------------------------
-- 6. insert_quick_order priced from the product.
--    DROP + CREATE, never CREATE OR REPLACE with an added parameter: that
--    creates a second overload and makes existing calls ambiguous -- the
--    failure set_order_status hit earlier in this project.
-- ---------------------------------------------------------------------
drop function if exists insert_quick_order(
  uuid, double precision, double precision, integer, text,
  numeric, numeric, numeric, text, text, text, timestamptz, text, uuid);

create function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,        -- IGNORED: kept for caller compatibility
  p_delivery_fee numeric,    -- IGNORED: kept for caller compatibility
  p_total_amount numeric,    -- IGNORED: kept for caller compatibility
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null,
  p_product_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  s water_stations%rowtype;
  p station_products%rowtype;
  c container_types%rowtype;
  v_origin uuid;
  v_subtotal numeric(10,2);
  v_matches integer;
  -- Default ceiling per order; for the association to confirm.
  v_max_qty constant integer := 50;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select * into s from water_stations where id = p_station_id;
  if not found or not s.is_active or not s.is_colorum_verified then
    raise exception 'This station is not available for ordering.';
  end if;
  if not coalesce(s.accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;
  if p_jugs_ordered is null or p_jugs_ordered < 1 or p_jugs_ordered > v_max_qty then
    raise exception 'Please order a quantity between 1 and %.', v_max_qty;
  end if;
  if not exists (select 1 from station_products where station_id = p_station_id and is_available) then
    raise exception 'This station has not listed any products yet.';
  end if;

  if p_product_id is not null then
    select * into p from station_products where id = p_product_id and station_id = p_station_id;
    if not found then
      raise exception 'That product is not sold by this station.';
    end if;
  else
    -- Older app builds send water type + container instead of a product.
    if p_jug_type is not null then
      select * into p from station_products
        where station_id = p_station_id and water_type = p_water_type
          and container_code = p_jug_type and kind = 'refill';
    else
      select count(*) into v_matches from station_products
        where station_id = p_station_id and water_type = p_water_type
          and kind = 'refill' and is_available;
      if v_matches > 1 then
        raise exception 'Please choose a container.';
      elsif v_matches = 1 then
        select * into p from station_products
          where station_id = p_station_id and water_type = p_water_type
            and kind = 'refill' and is_available;
      end if;
    end if;
    if p.id is null then
      raise exception 'This station does not offer % water in that container.', coalesce(p_water_type, 'that');
    end if;
  end if;

  if not p.is_available then
    raise exception 'That product is currently unavailable.';
  end if;
  select * into c from container_types where code = p.container_code;
  if not found or not c.is_active then
    raise exception 'That container is no longer offered.';
  end if;

  v_subtotal := p_jugs_ordered * p.price;

  -- An exchanged empty only exists for refills of returnable containers.
  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(s.offers_jug_exchange, false)
      and p.kind = 'refill' and c.is_returnable
    then p_jug_exchange_origin_station_id
    else null
  end;

  insert into orders (
    station_id, customer_profile_id, guest_name, guest_phone,
    delivery_location, jugs_ordered, water_type, jug_type,
    subtotal, delivery_fee, total_amount, customer_phone, client_request_id, scheduled_for,
    jug_exchange_origin_station_id, product_id, unit_price, product_kind
  ) values (
    p_station_id,
    case when auth.uid() is not null then auth.uid() else null end,
    case when auth.uid() is null then p_guest_name else null end,
    case when auth.uid() is null then p_guest_phone else null end,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p.water_type, p.container_code,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin, p.id, p.price, p.kind
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 7. Drivers can't change what was bought or its price either.
-- ---------------------------------------------------------------------
create or replace function protect_order_financial_fields() returns trigger as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    if new.subtotal is distinct from old.subtotal
       or new.delivery_fee is distinct from old.delivery_fee
       or new.total_amount is distinct from old.total_amount
       or new.jugs_ordered is distinct from old.jugs_ordered
       or new.station_id is distinct from old.station_id
       or new.driver_worker_id is distinct from old.driver_worker_id
       or new.unit_price is distinct from old.unit_price
       or new.product_id is distinct from old.product_id
       or new.product_kind is distinct from old.product_kind
       or new.water_type is distinct from old.water_type
       or new.jug_type is distinct from old.jug_type then
      raise exception 'Drivers may not modify order financial, product, station, or assignment details.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- 8. Jug-ledger entries only for refills: buying a new container involves
--    no empty jug, so nothing crosses station lines. Same signature as the
--    live function, so this is a true replacement.
-- ---------------------------------------------------------------------
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
  v_is_owner_or_admin boolean;
  v_new_driver_station_id uuid;
  v_new_driver_clearance clearance_status;
begin
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  v_is_owner_or_admin := auth_has_role('wasa_admin')
    or exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid());

  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  if v_is_owner_or_admin then
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
      return;
    elsif o.status in ('pending', 'assigned') and p_new_status = 'cancelled' then
      update orders set status = 'cancelled' where id = p_order_id;
      return;
    elsif o.status = 'assigned' and p_new_status = 'pending' then
      update orders set status = 'pending', driver_worker_id = null where id = p_order_id;
      return;
    else
      raise exception 'Not a valid status change for a station owner.';
    end if;
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

-- ---------------------------------------------------------------------
-- 9. Order summaries carry the container's name and the kind of purchase,
--    so screens can say "3 x 500 mL bottle (new)" instead of "3 jugs".
--    Return types change, hence drop + create. Extra columns are ignored by
--    older app builds.
-- ---------------------------------------------------------------------
drop function if exists lookup_guest_order(uuid, text);
create function lookup_guest_order(p_order_id uuid, p_guest_phone text)
returns table (
  id uuid, station_name text, status order_status, jugs_ordered integer,
  water_type text, jug_type text, total_amount numeric, created_at timestamptz,
  container_label text, product_kind text, unit_price numeric
) as $$
begin
  return query
    select o.id, s.station_name, o.status, o.jugs_ordered, o.water_type, o.jug_type,
           o.total_amount, o.created_at, ct.label, o.product_kind, o.unit_price
    from orders o
    join water_stations s on s.id = o.station_id
    left join container_types ct on ct.code = o.jug_type
    where o.id = p_order_id and o.guest_phone = p_guest_phone;
end;
$$ language plpgsql security definer set search_path = public;

drop function if exists get_active_orders(uuid);
create function get_active_orders(p_station_id uuid)
returns table (
  id uuid, lat double precision, lng double precision, jugs_ordered integer,
  water_type text, jug_type text, container_label text, product_kind text,
  is_returnable boolean
) as $$
  select o.id,
         st_y(o.delivery_location::geometry) as lat,
         st_x(o.delivery_location::geometry) as lng,
         o.jugs_ordered,
         o.water_type,
         o.jug_type,
         ct.label,
         o.product_kind,
         coalesce(ct.is_returnable, o.jug_type in ('slim_5gal', 'round_5gal'))
  from orders o
  left join container_types ct on ct.code = o.jug_type
  where o.station_id = p_station_id
    and o.status in ('assigned', 'active');
$$ language sql stable;

-- ---------------------------------------------------------------------
-- 10. Migrate existing prices into products: every priced station gets a
--     refill product per offered water type x offered container, at its
--     current price. Unpriced stations get none -- they stay un-orderable
--     until the owner lists products, rather than being sold at P0.
-- ---------------------------------------------------------------------
insert into station_products (station_id, water_type, container_code, kind, price)
select ws.id, wt, jt, 'refill', ws.price_per_jug
from water_stations ws
cross join lateral unnest(ws.offered_water_types) as wt
cross join lateral unnest(
  case when cardinality(ws.offered_jug_types) > 0
       then ws.offered_jug_types::text[]
       else array['slim_5gal'] end
) as jt
where ws.price_per_jug > 0
  and wt in ('purified', 'mineral', 'alkaline', 'distilled')
on conflict (station_id, water_type, container_code, kind) do nothing;

-- Bring every station's derived columns in line with its products.
do $$
declare
  r record;
begin
  for r in select id from water_stations loop
    perform sync_station_from_products(r.id);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 11. Owners now set their own delivery fee (Products screen), so the
--     server refuses a negative one rather than trusting the app to.
-- ---------------------------------------------------------------------
alter table water_stations drop constraint if exists water_stations_delivery_fee_nonnegative;
alter table water_stations add constraint water_stations_delivery_fee_nonnegative check (delivery_fee >= 0);

-- ---------------------------------------------------------------------
-- supabase/patch_account_lifecycle.sql  (live migration 20260911151726)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_account_lifecycle.sql
--
-- Account deletion (Google Play requires an in-app way to delete an
-- account) and comment author names. Deletion itself runs in the
-- delete-account Edge Function, which uses the two service-role-only
-- functions defined here.
--
-- Decisions (association): a deleted customer's orders are anonymized, not
-- deleted; station owners, drivers and admins request deletion and WASA
-- admin completes it.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. "Who did it" references to profiles no longer block deleting a
--    profile. They become NULL and the record they describe stays: the jug
--    ledger, settlements, floor prices, posts, events, resources, incident
--    reports, website edits, and a closed station's order history.
--    (memberships, reviews, comments and reactions already cascade.)
--    Every insert path still requires these to be the signed-in user (RLS),
--    so allowing NULL doesn't let anyone post anonymously.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values
    ('water_stations', 'owner_profile_id'),
    ('water_stations', 'accreditation_override_by'),
    ('workers', 'profile_id'),
    ('worker_incidents', 'reported_by_profile_id'),
    ('orders', 'customer_profile_id'),
    ('jug_ledger_entries', 'recorded_by'),
    ('jug_settlements', 'proposed_by'),
    ('jug_settlements', 'confirmed_by'),
    ('floor_prices', 'set_by'),
    ('bulletins', 'posted_by'),
    ('worker_station_history', 'ended_by_profile_id'),
    ('resources', 'uploaded_by'),
    ('events', 'created_by'),
    ('web_page_sections', 'updated_by'),
    ('web_content_items', 'updated_by'),
    ('web_faq_entries', 'updated_by'),
    ('permit_type_labels', 'updated_by')
  ) as v(tbl, col)
  loop
    execute format('alter table public.%I alter column %I drop not null', r.tbl, r.col);
    execute format('alter table public.%I drop constraint if exists %I', r.tbl, r.tbl || '_' || r.col || '_fkey');
    execute format(
      'alter table public.%I add constraint %I foreign key (%I) references public.profiles(id) on delete set null',
      r.tbl, r.tbl || '_' || r.col || '_fkey', r.col);
  end loop;
end $$;

-- posted_by can now be NULL, and "NULL <> auth.uid()" is NULL, not true --
-- so the old check let a NULL through. RLS already required
-- posted_by = auth.uid(); this makes the trigger agree.
create or replace function validate_bulletin_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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
$$;

-- ---------------------------------------------------------------------
-- 2. Comment author names, stored on the comment. profiles is readable
--    only by its owner and admin, so joining it showed every other
--    commenter as "Resident". Bulletins already store author_name the
--    same way.
-- ---------------------------------------------------------------------
alter table bulletin_comments add column if not exists author_name text;

update bulletin_comments c
   set author_name = coalesce(nullif(trim(p.full_name), ''), 'Resident')
  from profiles p
 where p.id = c.profile_id and c.author_name is null;

update bulletin_comments set author_name = 'Resident' where author_name is null;

create or replace function set_comment_author_name()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Always from the profile, never from the client.
  select coalesce(nullif(trim(full_name), ''), 'Resident') into new.author_name
    from profiles where id = new.profile_id;
  new.author_name := coalesce(new.author_name, 'Resident');
  return new;
end;
$$;

drop trigger if exists trg_set_comment_author_name on bulletin_comments;
create trigger trg_set_comment_author_name
  before insert on bulletin_comments
  for each row execute function set_comment_author_name();

-- ---------------------------------------------------------------------
-- 3. Deletion requests from station owners, drivers and admins.
-- ---------------------------------------------------------------------
create table if not exists account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  reason text check (reason is null or char_length(reason) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'cancelled')),
  requested_at timestamptz not null default now()
);

create unique index if not exists account_deletion_requests_one_pending
  on account_deletion_requests (profile_id) where status = 'pending';

alter table account_deletion_requests enable row level security;
revoke all on account_deletion_requests from anon;

drop policy if exists deletion_requests_self_read on account_deletion_requests;
create policy deletion_requests_self_read on account_deletion_requests
  for select using (profile_id = auth.uid());

drop policy if exists deletion_requests_self_insert on account_deletion_requests;
create policy deletion_requests_self_insert on account_deletion_requests
  for insert with check (profile_id = auth.uid() and status = 'pending');

drop policy if exists deletion_requests_self_withdraw on account_deletion_requests;
create policy deletion_requests_self_withdraw on account_deletion_requests
  for update using (profile_id = auth.uid())
  with check (profile_id = auth.uid() and status = 'cancelled');

drop policy if exists deletion_requests_admin_all on account_deletion_requests;
create policy deletion_requests_admin_all on account_deletion_requests
  for all using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- 4. Anonymize what outlives the account. Orders keep their items and
--    amounts for the station's records; the name, phones and exact
--    address go (the location is snapped to a ~1 km grid). Posts read
--    "Former member" and lose their image (the file is removed by the
--    Edge Function).
-- ---------------------------------------------------------------------
create or replace function anonymize_account(p_profile uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- guest_name gets a neutral label rather than NULL: the customer_or_guest
  -- check requires an order to have a customer or a guest name.
  update orders
     set customer_profile_id = null,
         guest_name = 'Former customer',
         guest_phone = null,
         customer_phone = null,
         delivery_location = st_setsrid(
           st_makepoint(
             round(st_x(delivery_location::geometry)::numeric, 2)::float8,
             round(st_y(delivery_location::geometry)::numeric, 2)::float8),
           4326)::geography
   where customer_profile_id = p_profile;

  update bulletins
     set author_name = 'Former member',
         author_station_name = null,
         image_url = null
   where posted_by = p_profile;
end;
$$;

revoke all on function anonymize_account(uuid) from public, anon, authenticated;
grant execute on function anonymize_account(uuid) to service_role;

-- ---------------------------------------------------------------------
-- 5. What stops an account from being deleted right now, each worded as
--    the step that clears it. Empty means it can go.
-- ---------------------------------------------------------------------
create or replace function account_deletion_blockers(p_profile uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_blockers text[] := array[]::text[];
  v_count int;
  v_station record;
begin
  select count(*) into v_count
    from orders
   where customer_profile_id = p_profile and status in ('pending', 'assigned', 'active');
  if v_count > 0 then
    v_blockers := array_append(v_blockers,
      format('%s order(s) still in progress. Wait for delivery or cancel them first.', v_count));
  end if;

  for v_station in
    select station_name from water_stations where owner_profile_id = p_profile and is_active
  loop
    v_blockers := array_append(v_blockers,
      format('Still the owner of %s, which is open. Close the station first.', v_station.station_name));
  end loop;

  select count(*) into v_count
    from orders o join workers w on w.id = o.driver_worker_id
   where w.profile_id = p_profile and o.status in ('assigned', 'active');
  if v_count > 0 then
    v_blockers := array_append(v_blockers,
      format('%s delivery(ies) assigned to this driver. Reassign or finish them first.', v_count));
  end if;

  if exists (select 1 from memberships where profile_id = p_profile and role = 'wasa_admin' and status = 'active')
     and (select count(*) from memberships where role = 'wasa_admin' and status = 'active') <= 1 then
    v_blockers := array_append(v_blockers, 'This is the only active WASA admin account. Add another admin first.');
  end if;

  return v_blockers;
end;
$$;

revoke all on function account_deletion_blockers(uuid) from public, anon, authenticated;
grant execute on function account_deletion_blockers(uuid) to service_role;

-- ---------------------------------------------------------------------
-- supabase/patch_notifications.sql  (live migration 20260911235109)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_notifications.sql
--
-- Nothing in the product ever told anyone anything: a customer didn't
-- learn their order was accepted, an owner didn't learn an order arrived,
-- a driver didn't learn they were assigned. This adds an in-app inbox fed
-- by database triggers, so the message is written once, server-side, for
-- every client.
--
-- It also publishes `orders` for Realtime. The owner's Orders screen has
-- always subscribed to live updates (orders_screen.dart), but no table was
-- published, so that "live" list only ever refreshed when reopened.
--
-- Phone push (FCM) is deliberately not here -- it needs the association's
-- final app ID. It will read the same rows.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The inbox. Written only by the triggers below (SECURITY DEFINER):
--    there is no insert policy, so no client can post a notification.
-- ---------------------------------------------------------------------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  category text not null check (category in ('order', 'permit', 'accreditation', 'account')),
  title text not null,
  body text,
  order_id uuid references orders(id) on delete set null,
  station_id uuid references water_stations(id) on delete set null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_profile_created_idx
  on notifications (profile_id, created_at desc);

alter table notifications enable row level security;
revoke all on notifications from anon;

drop policy if exists notifications_self_read on notifications;
create policy notifications_self_read on notifications
  for select using (profile_id = auth.uid());

drop policy if exists notifications_self_mark_read on notifications;
create policy notifications_self_mark_read on notifications
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());

drop policy if exists notifications_self_delete on notifications;
create policy notifications_self_delete on notifications
  for delete using (profile_id = auth.uid());

-- ---------------------------------------------------------------------
-- 2. One order line, worded the same way the app words it
--    (describeOrderLine, lib/models/order.dart).
-- ---------------------------------------------------------------------
create or replace function order_line_text(
  p_quantity integer,
  p_water_type text,
  p_container_code text,
  p_product_kind text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_label text;
  v_water text := initcap(coalesce(p_water_type, ''));
begin
  select label into v_label from container_types where code = p_container_code;
  if v_label is null then
    return p_quantity || ' × ' || v_water;
  end if;
  return p_quantity || ' × ' || v_label
    || case p_product_kind when 'refill' then ' refill' when 'new_container' then ' (new)' else '' end
    || case when v_water = '' then '' else ' · ' || v_water end;
end;
$$;

create or replace function peso_text(p_amount numeric)
returns text language sql immutable as $$
  select '₱' || trim(to_char(coalesce(p_amount, 0), 'FM999999990.00'));
$$;

-- ---------------------------------------------------------------------
-- 3. Order events -> the people they concern.
-- ---------------------------------------------------------------------
create or replace function notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_station_name text;
  v_driver_profile uuid;
  v_line text;
begin
  select owner_profile_id, station_name into v_owner, v_station_name
    from water_stations where id = new.station_id;
  v_line := order_line_text(new.jugs_ordered, new.water_type, new.jug_type, new.product_kind);

  -- A new order: the station owner needs to see it.
  if tg_op = 'INSERT' then
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id);
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
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

  -- Assigned to a driver (status and driver can change in the same update).
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

drop trigger if exists trg_notify_order_event on orders;
create trigger trg_notify_order_event
  after insert or update on orders
  for each row execute function notify_order_event();

-- ---------------------------------------------------------------------
-- 4. Permit decisions and accreditation changes -> the station owner.
-- ---------------------------------------------------------------------
create or replace function notify_permit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_station text;
  v_label text;
begin
  if new.status is not distinct from old.status or new.status not in ('approved', 'rejected') then
    return new;
  end if;

  select owner_profile_id, station_name into v_owner, v_station
    from water_stations where id = new.station_id;
  if v_owner is null then
    return new;
  end if;

  select label into v_label from permit_type_labels where permit_type = new.permit_type;
  v_label := coalesce(v_label, initcap(replace(new.permit_type::text, '_', ' ')));

  insert into notifications (profile_id, category, title, body, station_id)
  values (
    v_owner, 'permit',
    case new.status when 'approved' then v_label || ' approved' else v_label || ' was rejected' end,
    case
      when new.status = 'rejected' and new.rejection_reason is not null then new.rejection_reason
      else coalesce(v_station, '')
    end,
    new.station_id);
  return new;
end;
$$;

drop trigger if exists trg_notify_permit_review on permits;
create trigger trg_notify_permit_review
  after update on permits
  for each row execute function notify_permit_review();

create or replace function notify_accreditation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.accreditation_status::text is not distinct from old.accreditation_status::text
     or new.owner_profile_id is null then
    return new;
  end if;

  insert into notifications (profile_id, category, title, body, station_id)
  values (
    new.owner_profile_id, 'accreditation',
    case new.accreditation_status::text
      when 'accredited' then 'Your station is accredited'
      else 'Accreditation status: ' || replace(new.accreditation_status::text, '_', ' ')
    end,
    new.station_name, new.id);
  return new;
end;
$$;

drop trigger if exists trg_notify_accreditation_change on water_stations;
create trigger trg_notify_accreditation_change
  after update on water_stations
  for each row execute function notify_accreditation_change();

-- ---------------------------------------------------------------------
-- 5. Realtime. Row-level security still applies to what each client
--    receives, so everyone only ever sees their own rows.
-- ---------------------------------------------------------------------
alter table notifications replica identity full;
alter table orders replica identity full;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'notifications') then
    alter publication supabase_realtime add table notifications;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'orders') then
    alter publication supabase_realtime add table orders;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- supabase/patch_customer_addresses.sql  (live migration 20260912012730)
-- ---------------------------------------------------------------------
-- =====================================================================
-- patch_customer_addresses.sql
--
-- Customers had to drop a pin on the map for every single order, even
-- when ordering to the same house every week. This stores the places a
-- customer orders to, labelled, with one default that the order form
-- pre-selects.
--
-- Only the customer can see or change their own; the address only reaches
-- a station through the order they place (orders.delivery_location),
-- exactly as before.
-- =====================================================================

create table if not exists customer_addresses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 40),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  notes text check (notes is null or char_length(notes) <= 200),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists customer_addresses_profile_idx on customer_addresses (profile_id, created_at);

-- At most one default each, enforced rather than hoped for.
create unique index if not exists customer_addresses_one_default
  on customer_addresses (profile_id) where is_default;

alter table customer_addresses enable row level security;
revoke all on customer_addresses from anon;

drop policy if exists customer_addresses_self_all on customer_addresses;
create policy customer_addresses_self_all on customer_addresses
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Marking one default clears the previous one, so saving never fails on
-- the unique index above.
create or replace function enforce_single_default_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_default then
    update customer_addresses
       set is_default = false
     where profile_id = new.profile_id and id <> new.id and is_default;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_single_default_address on customer_addresses;
create trigger trg_enforce_single_default_address
  before insert or update on customer_addresses
  for each row execute function enforce_single_default_address();

-- ---------------------------------------------------------------------
-- supabase/migrations/0011_favorite_stations.sql
--
-- A customer's own shortlist of member stations. Purely a per-customer
-- preference -- it grants no access to anything and is never visible to
-- the station. The directory pins favourites above the distance-sorted
-- remainder, and the ordering screen prefers a favourite over the nearest
-- station.
-- ---------------------------------------------------------------------
create table if not exists favorite_stations (
  profile_id uuid not null references profiles(id) on delete cascade,
  station_id uuid not null references water_stations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, station_id)
);

create index if not exists favorite_stations_profile_idx on favorite_stations (profile_id);

alter table favorite_stations enable row level security;

drop policy if exists favorite_stations_self on favorite_stations;
create policy favorite_stations_self on favorite_stations for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());


-- ---------------------------------------------------------------------
-- supabase/patch_flagged_driver_rejoin.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a flagged driver could rejoin the association by re-registering.
--
-- There are two ways a driver joins a station, and only one of them
-- checked clearance:
--
--   driver_switch_station()        raises if clearance_status = 'flagged'
--   register_driver_for_station()  did not check at all
--
-- So the sequence below let a flagged driver straight back in:
--
--   1. Station A files an incident; a WASA admin confirms it, which sets
--      the worker's clearance_status to 'flagged'.
--   2. Station A removes the driver (owner_remove_worker), leaving
--      workers.station_id null.
--   3. The driver enters any station's invite code.
--   4. register_driver_for_station() takes its "previously left/removed"
--      re-link branch, which never looked at clearance, and adds them to
--      the new station's roster.
--
-- A driver who was NOT removed is blocked by driver_switch_station. Being
-- removed after an incident therefore made it easier to move, not harder
-- -- the opposite of what the worker security registry exists to do, and
-- the opposite of what the public website states:
--
--   "Maintains a shared worker security registry, so a driver flagged for
--    an incident at one station can't simply move to another unnoticed."
--
-- Found during the functionality evaluation of 10 October 2026, while
-- checking an evaluator's observation that the station invite code never
-- rotates -- which is what makes step 3 easy, since a removed driver
-- already knows it.
--
-- The check below is deliberately worded like the one in
-- driver_switch_station, so a flagged driver gets the same explanation
-- whichever route they try.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

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
  v_current_station_id uuid;
  v_clearance clearance_status;
begin
  select id, station_id, clearance_status
    into v_worker_id, v_current_station_id, v_clearance
    from workers where profile_id = auth.uid();

  if v_worker_id is not null then
    if v_current_station_id is not null then
      return v_worker_id;
    end if;

    -- The fix. Checked only on the re-link branch: a brand new worker
    -- (further down) starts at 'pending_clearance', which must stay
    -- joinable or nobody could ever register in the first place.
    if v_clearance = 'flagged' then
      raise exception 'Cannot join a station while flagged. Contact WASA to resolve outstanding incidents.';
    end if;

    -- Previously left/removed from a station -- re-link to the new one
    -- instead of silently returning a stale, still-unlinked id.
    select id, association_id into v_station_id, v_association_id
      from water_stations where invite_code ilike p_invite_code;
    if v_station_id is null then
      raise exception 'Invalid station invite code.';
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

-- ---------------------------------------------------------------------
-- supabase/patch_overhaul_gaps.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Gaps found during the October 2026 evaluation and the UI overhaul.
--
-- Idempotent -- safe to run more than once. Run after every earlier patch
-- (it replaces notify_order_event and the incidents/bulletins read
-- policies). Each section says what was missing and why it matters.
--
--   1. Station invite codes could never be changed
--   2. Owners could read other stations' incident reports
--   3. No record of privacy-notice consent at sign-up
--   4. A driver had no way to report a failed delivery
--   5. Bulletin posts could not be reported or hidden
--   6. A flagged driver had no way to appeal
--   7. No audit log of who changed what
--   8. Website content edits could not be undone
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Notification categories used below.
-- ---------------------------------------------------------------------
alter table notifications drop constraint if exists notifications_category_check;
alter table notifications add constraint notifications_category_check
  check (category in ('order', 'permit', 'accreditation', 'account', 'worker', 'bulletin'));

-- ---------------------------------------------------------------------
-- 1. Regenerate a station's invite code.
--
-- The code was set once at registration and never changed. An evaluator
-- pointed out that a removed driver therefore always knows it -- which is
-- what made the flagged-driver rejoin (patch_flagged_driver_rejoin.sql)
-- easy. An owner can now issue a new code; the old one stops working.
-- Same alphabet and length as registration_screen.dart's generator.
-- ---------------------------------------------------------------------
create or replace function owner_regenerate_invite_code() returns text as $$
declare
  v_station_id uuid;
  v_code text;
  v_chars constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  i int;
begin
  select id into v_station_id from water_stations where owner_profile_id = auth.uid() limit 1;
  if v_station_id is null then
    raise exception 'Only a station owner can change the invite code.';
  end if;

  for attempt in 1..10 loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::int, 1);
    end loop;
    begin
      update water_stations set invite_code = v_code where id = v_station_id;
      return v_code;
    exception when unique_violation then
      -- Another station already has this code; try another.
    end;
  end loop;
  raise exception 'Could not generate a unique code. Please try again.';
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function owner_regenerate_invite_code() to authenticated;

-- ---------------------------------------------------------------------
-- 2. Incident privacy.
--
-- incidents_owner_read let an owner read every incident about any driver
-- currently on their roster -- including the full text of reports other
-- stations had filed before the driver moved. The registry's promise is
-- narrower: other stations learn *that* a driver is flagged (and how many
-- confirmed incidents), through hire_check_search, not what was written.
-- Owners now read the reports they filed; the driver can read the reports
-- about themselves (they need to, to appeal); officers read everything.
-- ---------------------------------------------------------------------
drop policy if exists incidents_owner_read on worker_incidents;
create policy incidents_owner_read on worker_incidents for select
  using (reported_by_profile_id = auth.uid());

drop policy if exists incidents_self_read on worker_incidents;
create policy incidents_self_read on worker_incidents for select
  using (worker_id in (select id from workers where profile_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 3. Privacy-notice consent.
--
-- Sign-up never recorded agreement to the privacy notice (RA 10173 expects
-- consent to be demonstrable). The app now requires the box to be ticked
-- and calls this once the account exists.
-- ---------------------------------------------------------------------
alter table profiles add column if not exists privacy_consented_at timestamptz;
alter table profiles add column if not exists privacy_notice_version text;

create or replace function record_privacy_consent(p_version text) returns void as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;
  update profiles
     set privacy_consented_at = now(), privacy_notice_version = p_version, updated_at = now()
   where id = auth.uid();
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function record_privacy_consent(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Failed deliveries.
--
-- A driver who couldn't deliver (nobody home, wrong address) had two
-- options: mark it delivered anyway, or leave it hanging. Now they report
-- it with a reason; the order goes back to the station's queue, unassigned,
-- so the owner can reassign or cancel it, and the customer is told why.
-- ---------------------------------------------------------------------
alter table orders add column if not exists failure_reason text;
alter table orders add column if not exists failed_at timestamptz;

create or replace function driver_report_failed_delivery(p_order_id uuid, p_reason text) returns void as $$
declare
  o orders%rowtype;
  v_worker_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Say why the delivery could not be completed.';
  end if;

  select id into v_worker_id from workers where profile_id = auth.uid();
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;
  if v_worker_id is null or o.driver_worker_id is distinct from v_worker_id then
    raise exception 'Only the assigned driver can report this delivery.';
  end if;
  if o.status not in ('assigned', 'active') then
    raise exception 'This order is not out for delivery.';
  end if;

  update orders
     set status = 'pending',
         driver_worker_id = null,
         failure_reason = trim(p_reason),
         failed_at = now()
   where id = p_order_id;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_report_failed_delivery(uuid, text) to authenticated;

-- notify_order_event, as in patch_notifications.sql, plus the failed
-- delivery case: the customer hears why, and the owner is asked to act.
create or replace function notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'New order', v_line || ' · ' || peso_text(new.total_amount), new.id, new.station_id);
    end if;
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
    if v_owner is not null then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (v_owner, 'order', 'Delivery failed: reassign or cancel',
              v_line || ' · ' || new.failure_reason, new.id, new.station_id);
    end if;
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

drop trigger if exists trg_notify_order_event on orders;
create trigger trg_notify_order_event
  after insert or update on orders
  for each row execute function notify_order_event();

-- ---------------------------------------------------------------------
-- 5. Bulletin moderation.
--
-- Members can post and comment, but nobody could flag a post, and the only
-- moderation was outright deletion. Any signed-in member can now report a
-- post with a reason; officers see the reports and can hide a post (kept
-- for the record, gone from every feed) or unhide it.
-- ---------------------------------------------------------------------
alter table bulletins add column if not exists is_hidden boolean not null default false;
alter table bulletins add column if not exists hidden_by uuid references profiles(id) on delete set null;
alter table bulletins add column if not exists hidden_at timestamptz;
