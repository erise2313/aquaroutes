-- GENTRI WASA setup -- PART 3 of 6. Run the parts in order,
-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)

create table if not exists bulletin_reports (
  id uuid primary key default gen_random_uuid(),
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  reported_by uuid not null default auth.uid() references profiles(id) on delete cascade,
  reason text not null check (length(trim(reason)) > 0),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references profiles(id) on delete set null,
  unique (bulletin_id, reported_by)
);

create index if not exists bulletin_reports_open_idx on bulletin_reports (bulletin_id) where resolved_at is null;

alter table bulletin_reports enable row level security;

drop policy if exists bulletin_reports_insert on bulletin_reports;
create policy bulletin_reports_insert on bulletin_reports for insert
  with check (auth.uid() is not null and reported_by = auth.uid());

drop policy if exists bulletin_reports_read on bulletin_reports;
create policy bulletin_reports_read on bulletin_reports for select
  using (reported_by = auth.uid() or auth_has_role('wasa_admin'));

drop policy if exists bulletin_reports_admin_update on bulletin_reports;
create policy bulletin_reports_admin_update on bulletin_reports for update
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- Hidden posts drop out of every feed except for officers and the author.
drop policy if exists bulletins_public_read on bulletins;
create policy bulletins_public_read on bulletins for select
  using (not is_hidden or auth_has_role('wasa_admin') or posted_by = auth.uid());

-- ---------------------------------------------------------------------
-- 6. Driver appeals.
--
-- A confirmed incident flags a driver across every station, and there was
-- no way to contest it. The driver can now appeal a confirmed incident once,
-- in writing; officers uphold it or overturn it. Overturning dismisses the
-- incident, and apply_incident_resolution clears the flag if no other
-- confirmed incident remains.
-- ---------------------------------------------------------------------
alter table worker_incidents add column if not exists appeal_text text;
alter table worker_incidents add column if not exists appeal_status text;
alter table worker_incidents drop constraint if exists worker_incidents_appeal_status_check;
alter table worker_incidents add constraint worker_incidents_appeal_status_check
  check (appeal_status is null or appeal_status in ('pending', 'upheld', 'overturned'));
alter table worker_incidents add column if not exists appeal_submitted_at timestamptz;
alter table worker_incidents add column if not exists appeal_decided_at timestamptz;
alter table worker_incidents add column if not exists appeal_decided_by uuid references profiles(id) on delete set null;
alter table worker_incidents add column if not exists appeal_decision_note text;

create or replace function driver_submit_appeal(p_incident_id uuid, p_text text) returns void as $$
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
   where m.role = 'wasa_admin' and m.status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_submit_appeal(uuid, text) to authenticated;

create or replace function admin_decide_appeal(p_incident_id uuid, p_overturn boolean, p_note text) returns void as $$
declare
  inc worker_incidents%rowtype;
  v_driver_profile uuid;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can decide appeals.';
  end if;
  if p_note is null or length(trim(p_note)) = 0 then
    raise exception 'Give a reason for the decision.';
  end if;

  select * into inc from worker_incidents where id = p_incident_id for update;
  if not found or inc.appeal_status is distinct from 'pending' then
    raise exception 'There is no pending appeal on this incident.';
  end if;

  update worker_incidents
     set appeal_status = case when p_overturn then 'overturned' else 'upheld' end,
         appeal_decided_at = now(),
         appeal_decided_by = auth.uid(),
         appeal_decision_note = trim(p_note),
         status = case when p_overturn then 'dismissed'::incident_status else status end,
         resolved_by = case when p_overturn then auth.uid() else resolved_by end,
         resolved_at = case when p_overturn then now() else resolved_at end
   where id = p_incident_id;

  select profile_id into v_driver_profile from workers where id = inc.worker_id;
  if v_driver_profile is not null then
    insert into notifications (profile_id, category, title, body)
    values (v_driver_profile, 'worker',
            case when p_overturn then 'Your appeal was accepted' else 'Your appeal was not accepted' end,
            trim(p_note));
  end if;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function admin_decide_appeal(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------
-- 7. Audit log.
--
-- The Activity page was assembled from reviewed_by/updated_by columns, so
-- it could only say who last touched a row -- not what changed, and nothing
-- at all for role changes or suspensions. audit_log records every change
-- to the records officers are accountable for, with before and after.
-- Written only by triggers; there is no insert, update or delete policy, so
-- nobody can edit or remove an entry from the app.
-- ---------------------------------------------------------------------
create table if not exists audit_log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid references profiles(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  summary text not null,
  before jsonb,
  after jsonb
);

create index if not exists audit_log_occurred_idx on audit_log (occurred_at desc);
create index if not exists audit_log_table_idx on audit_log (table_name, occurred_at desc);

alter table audit_log enable row level security;

drop policy if exists audit_log_admin_read on audit_log;
create policy audit_log_admin_read on audit_log for select
  using (auth_has_role('wasa_admin'));

create or replace function audit_row_change() returns trigger as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
  o jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  n jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  v_summary text;
begin
  v_summary := case tg_table_name
    when 'permits' then
      'Permit ' || replace(r->>'permit_type', '_', ' ') || ': ' || replace(coalesce(n->>'status', 'deleted'), '_', ' ')
    when 'water_stations' then
      'Station ' || coalesce(r->>'station_name', '') || ': accreditation '
        || replace(coalesce(n->>'accreditation_status', ''), '_', ' ')
    when 'memberships' then
      'Membership ' || coalesce(r->>'role', '') || ': '
        || case tg_op when 'INSERT' then 'added' when 'DELETE' then 'removed' else coalesce(n->>'status', '') end
    when 'worker_incidents' then
      'Incident ' || coalesce(r->>'incident_type', '') || ': ' || replace(coalesce(n->>'status', 'deleted'), '_', ' ')
        || case when n->>'appeal_status' is not null then ' (appeal ' || (n->>'appeal_status') || ')' else '' end
    when 'jug_settlements' then
      'Jug settlement of ' || coalesce(r->>'quantity', '?') || ': ' || coalesce(n->>'status', 'deleted')
    when 'bulletins' then
      'Bulletin "' || left(coalesce(r->>'title', ''), 60) || '": '
        || case when tg_op = 'DELETE' then 'deleted'
                when (n->>'is_hidden')::boolean then 'hidden'
                when (o->>'is_hidden')::boolean then 'unhidden'
                else 'updated' end
    else
      initcap(replace(tg_table_name, '_', ' ')) || ' ' || lower(tg_op)
  end;

  insert into audit_log (actor_id, action, table_name, record_id, summary, before, after)
  values (auth.uid(), lower(tg_op), tg_table_name, r->>'id', v_summary, o, n);
  return coalesce(new, old);
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_audit_permits on permits;
create trigger trg_audit_permits
  after update of status, expiry_date, is_required on permits
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_stations on water_stations;
create trigger trg_audit_stations
  after update of is_accredited, accreditation_status, owner_profile_id on water_stations
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_memberships on memberships;
create trigger trg_audit_memberships
  after insert or delete or update of role, status on memberships
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_incidents on worker_incidents;
create trigger trg_audit_incidents
  after insert or update of status, appeal_status on worker_incidents
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_settlements on jug_settlements;
create trigger trg_audit_settlements
  after insert or update of status on jug_settlements
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_bulletins on bulletins;
create trigger trg_audit_bulletins
  after delete or update of is_hidden, is_pinned on bulletins
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_sections on web_page_sections;
create trigger trg_audit_web_sections
  after insert or update or delete on web_page_sections
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_items on web_content_items;
create trigger trg_audit_web_items
  after insert or update or delete on web_content_items
  for each row execute function audit_row_change();

drop trigger if exists trg_audit_web_faq on web_faq_entries;
create trigger trg_audit_web_faq
  after insert or update or delete on web_faq_entries
  for each row execute function audit_row_change();

-- ---------------------------------------------------------------------
-- 8. Website content history.
--
-- Saving a page section overwrote it for good. Every update or delete of
-- website content now keeps the previous version, and an officer can
-- restore one.
-- ---------------------------------------------------------------------
create table if not exists web_content_revisions (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid not null,
  snapshot jsonb not null,
  changed_by uuid references profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index if not exists web_content_revisions_record_idx on web_content_revisions (table_name, record_id, changed_at desc);

alter table web_content_revisions enable row level security;

drop policy if exists web_content_revisions_admin_read on web_content_revisions;
create policy web_content_revisions_admin_read on web_content_revisions for select
  using (auth_has_role('wasa_admin'));

create or replace function keep_web_content_revision() returns trigger as $$
begin
  insert into web_content_revisions (table_name, record_id, snapshot, changed_by)
  values (tg_table_name, old.id, to_jsonb(old), auth.uid());
  return coalesce(new, old);
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_revision_web_sections on web_page_sections;
create trigger trg_revision_web_sections
  before update or delete on web_page_sections
  for each row execute function keep_web_content_revision();

drop trigger if exists trg_revision_web_items on web_content_items;
create trigger trg_revision_web_items
  before update or delete on web_content_items
  for each row execute function keep_web_content_revision();

drop trigger if exists trg_revision_web_faq on web_faq_entries;
create trigger trg_revision_web_faq
  before update or delete on web_faq_entries
  for each row execute function keep_web_content_revision();

-- Puts a saved version back. A restore is itself an update, so the version
-- being replaced is kept too -- a restore can always be undone.
create or replace function restore_web_content_revision(p_revision_id bigint) returns void as $$
declare
  rev web_content_revisions%rowtype;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can restore website content.';
  end if;
  select * into rev from web_content_revisions where id = p_revision_id;
  if not found then
    raise exception 'That version no longer exists.';
  end if;

  if rev.table_name = 'web_page_sections' then
    update web_page_sections
       set title = rev.snapshot->>'title', body = rev.snapshot->>'body',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  elsif rev.table_name = 'web_content_items' then
    update web_content_items
       set title = rev.snapshot->>'title', body = rev.snapshot->>'body', icon = rev.snapshot->>'icon',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  elsif rev.table_name = 'web_faq_entries' then
    update web_faq_entries
       set question = rev.snapshot->>'question', answer = rev.snapshot->>'answer',
           updated_by = auth.uid(), updated_at = now()
     where id = rev.record_id;
  else
    raise exception 'Unknown content type.';
  end if;

  if not found then
    raise exception 'The item this version belonged to has been deleted.';
  end if;
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function restore_web_content_revision(bigint) to authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_advisor_hardening.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Hardening from Supabase's security advisor, 17 October 2026.
--
-- Idempotent -- safe to run more than once. Run after every earlier patch.
--
-- 1. Jug balances were readable by anyone holding the publishable key.
--
--    jug_balances is a view over jug_ledger_entries. Views run with their
--    creator's rights by default, which skips the ledger's RLS -- so
--    `select * from jug_balances` with the key that ships in every APK and
--    web build returned every station's balances with every other station,
--    signed in or not. The ledger's own policies already say who should see
--    what (an owner: rows their station is part of; officers: everything),
--    so the view now runs with the caller's rights and those policies apply.
--    The clearinghouse screen already filters to the owner's station, so it
--    sees exactly what it did before. Drivers never read this view.
--
--    bulletin_reaction_counts gets the same switch. Reactions are publicly
--    readable anyway, so nothing changes for anyone; it just stops being an
--    exception to RLS.
--
--    public_stations deliberately stays as it is: it is the public
--    directory -- a fixed set of columns from accredited, active stations --
--    and water_stations' RLS rightly hides those rows from visitors.
--
-- 2. Seven functions did not pin search_path.
--
--    Without it a function resolves table and function names through the
--    caller's search_path, which a caller can change. Pinned to public,
--    matching every security definer function in this project.
--
-- 3. sync_station_from_products() could be called by anyone.
--
--    It recomputes a station's prices and water types from its products,
--    and is meant to run only from the two triggers that call it (both
--    security definer, so they keep the right to). Called directly it
--    did no harm beyond needless work, but it has no reason to be public.
-- =====================================================================

-- 1.
alter view jug_balances set (security_invoker = true);
alter view bulletin_reaction_counts set (security_invoker = true);

-- 2.
-- get_pending_orders is left over from the first prototype and is not
-- created by this script, so a brand-new project doesn't have it.
do $$ begin
  if to_regprocedure('public.get_pending_orders(uuid)') is not null then
    alter function get_pending_orders(uuid) set search_path = public;
  end if;
end $$;
alter function get_active_orders(uuid) set search_path = public;
alter function generate_worker_code() set search_path = public;
alter function peso_text(numeric) set search_path = public;
alter function stamp_accredited_at() set search_path = public;
alter function stamp_accredited_at_insert() set search_path = public;
alter function station_products_touch_updated_at() set search_path = public;

-- 3.
revoke execute on function sync_station_from_products(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_failed_delivery_fix.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Fix: a driver's "Couldn't deliver" always failed.
--
-- driver_report_failed_delivery() (patch_overhaul_gaps.sql) puts the order
-- back in the station's queue by clearing driver_worker_id. The older
-- protect_order_financial_fields trigger (patch_audit_remediation.sql)
-- refuses any change to driver_worker_id unless the signed-in user is an
-- owner or an officer -- and it looks at who is signed in, not at which
-- function is doing the update, so it refused the driver's own report:
--
--   "Drivers may not modify order financial, product, station, or
--    assignment details."
--
-- Found by running the test case GTW-APP-314 against the live database on
-- 17 October 2026. Starting and completing a delivery were unaffected:
-- neither touches driver_worker_id.
--
-- The trigger still guards every direct write. It now also lets through an
-- update that driver_report_failed_delivery() has vouched for, by setting
-- a transaction-local flag around its one update. Clients can't set that
-- flag: they reach the database only through PostgREST, which exposes the
-- public schema's tables and functions, not set_config().
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function protect_order_financial_fields() returns trigger as $$
begin
  -- An update a trusted function has already checked (see above).
  if current_setting('gentri.trusted_order_change', true) = 'on' then
    return new;
  end if;

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

  -- Checked above, so vouch for this one update to
  -- protect_order_financial_fields, then withdraw it.
  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders
     set status = 'pending',
         driver_worker_id = null,
         failure_reason = trim(p_reason),
         failed_at = now()
   where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function driver_report_failed_delivery(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_signed_in_ordering.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Ordering requires a signed-in customer account -- on the server too.
--
-- The app stopped offering guest checkout some time ago: the order form
-- shows a sign-in gate to visitors (quick_order_screen.dart), so every order
-- is tied to a real account. The server never followed. insert_quick_order
-- still accepted calls from signed-out visitors, holding nothing but the
-- publishable key that ships in every APK and web build, and stored them as
-- guest orders -- so anyone could skip the app and send stations orders that
-- no account stood behind.
--
-- This patch:
--
--   1. insert_quick_order refuses anyone who isn't a signed-in, active
--      customer, and records the order against that account. p_guest_name
--      and p_guest_phone keep their places in the signature so the app
--      doesn't break mid-update; p_guest_phone now only carries the contact
--      number for the delivery (orders.customer_phone), as it already did
--      for signed-in orders.
--
--   2. The guest-tracking path goes. A guest could look an order up, follow
--      its driver on the map and cancel it with the order ID and checkout
--      phone number. With no new guest orders that path only served three
--      old, closed orders (the last placed 11 September 2026), so:
--        - get_active_delivery_driver answers only the customer who placed
--          the order;
--        - lookup_guest_order is no longer callable from the app;
--        - signed-out visitors can no longer call set_order_status, whose
--          guest-cancel branch they were the only route into.
--
-- The old guest orders stay in the database, unchanged, for the record.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

-- 1.
create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered integer,
  p_water_type text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total_amount numeric,
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
  v_max_qty constant integer := 50;
begin
  if auth.uid() is null then
    raise exception 'Sign in to place an order.';
  end if;
  if not auth_has_role('public_consumer') then
    raise exception 'Only customer accounts can place orders.';
  end if;

  if p_client_request_id is not null then
    -- A retried submit returns the order it already created -- but only
    -- the caller's own, so a request id can't fish out someone else's.
    select id into new_order_id from orders
     where client_request_id = p_client_request_id and customer_profile_id = auth.uid();
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
    p_station_id, auth.uid(), null, null,
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
    p_jugs_ordered, p.water_type, p.container_code,
    v_subtotal, s.delivery_fee, v_subtotal + s.delivery_fee,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin, p.id, p.price, p.kind
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- 2.
create or replace function get_active_delivery_driver(p_order_id uuid, p_guest_phone text default null)
returns table(driver_name text, driver_phone text, lat double precision, lng double precision, last_updated timestamptz)
as $$
declare
  v_order orders%rowtype;
begin
  -- p_guest_phone is ignored; it stays in the signature for older builds.
  select * into v_order from orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found.';
  end if;

  if auth.uid() is null or v_order.customer_profile_id is distinct from auth.uid() then
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

revoke execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) from public, anon;
grant execute on function insert_quick_order(uuid, double precision, double precision, integer, text, numeric, numeric, numeric, text, text, text, timestamptz, text, uuid, uuid) to authenticated;

revoke execute on function get_active_delivery_driver(uuid, text) from public, anon;
grant execute on function get_active_delivery_driver(uuid, text) to authenticated;

revoke execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) from public, anon;
grant execute on function set_order_status(uuid, order_status, uuid, text, integer, boolean, uuid, boolean) to authenticated;

revoke execute on function lookup_guest_order(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- supabase/patch_roles_governance.sql (patch_roles_enum.sql is folded into
-- the app_role definition above)
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- supabase/patch_compliance.sql
-- ---------------------------------------------------------------------
-- =====================================================================
-- Compliance automation, official notices and compliance cases
-- (UI/Roles plan Phase 3, Rollout plan "Fighting non-compliance").
-- Run after patch_roles_governance.sql. Idempotent.
--
--  1. Each permit type has a validity (the water test is monthly) and a
--     plain-language description for the owner's checklist. Approving a
--     permit with no expiry set gives it review date + validity; the
--     officer's own date still wins.
--  2. Driver licences carry an expiry date too.
--  3. Every station has a standing, worked out the same way for everyone:
--       applicant  never accredited yet
--       good       accredited, nothing expired
--       warning    a required permit expired, still within the grace period
--                  (or a renewal is waiting for review)
--       lapsed     a required permit expired past the grace period: the
--                  Accredited badge comes off. The station can still take
--                  orders (board decision, 18 Oct 2026) and is shown as
--                  Lapsed.
--       suspended  closed by WASA
--     The grace period is association_settings.grace_days (set by a super
--     admin).
--  4. A daily job (pg_cron, 06:00 Philippine time) sends reminders 30 and
--     7 days before a permit or licence expires and when it does, then
--     re-works every station's standing. Each reminder is sent once.
--  5. Official notices from WASA to one station or all, with read and
--     acknowledgement receipts.
--  6. Compliance cases: a written record of each issue (permit, water test,
--     conduct, complaint -- never price), the decision, the officer and the
--     station's written response.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Permit validity and descriptions
-- ---------------------------------------------------------------------
alter table permit_type_labels add column if not exists validity_months int check (validity_months is null or validity_months > 0);
alter table permit_type_labels add column if not exists description text;

update permit_type_labels l set
  validity_months = coalesce(l.validity_months, v.months),
  description = coalesce(l.description, v.description)
from (values
  ('business_permit', 12, 'The city''s permit to operate a business. Renewed every year, usually in January.'),
  ('sanitary_permit', 12, 'Issued by the City Health Office after an inspection of the station. Renewed yearly.'),
  ('fda_license', 24, 'FDA License to Operate for a water refilling station.'),
  ('fire_safety_certificate', 12, 'Fire Safety Inspection Certificate from the Bureau of Fire Protection. Yearly.'),
  ('water_quality_test_report', 1, 'Monthly bacteriological test of your water by a DOH-accredited laboratory. Upload each month''s result.'),
  ('operator_training_certificate', null, 'Certificate from the operator''s water safety training. Replace it if the operator changes.'),
  ('alkaline_tech_cert', null, 'Technical certification of the alkaline machine. Only for stations selling alkaline water.'),
  ('alkaline_water_test', 6, 'Quality test of the alkaline water, every six months. Only for stations selling alkaline water.'),
  ('nwrb_water_permit', null, 'National Water Resources Board permit for the water source.'),
  ('nwrb_certificate_of_public_convenience', null, 'National Water Resources Board Certificate of Public Convenience.')
) as v(permit_type, months, description)
where l.permit_type::text = v.permit_type;

create or replace function permit_default_expiry() returns trigger as $$
declare
  v_months int;
begin
  if new.status = 'approved' and new.status is distinct from old.status and new.expiry_date is null then
    select validity_months into v_months from permit_type_labels where permit_type = new.permit_type;
    if v_months is not null then
      new.expiry_date := (current_date + make_interval(months => v_months))::date;
    end if;
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_permit_default_expiry') then
    create trigger trg_permit_default_expiry before update on permits
      for each row execute function permit_default_expiry();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Licence expiry
-- ---------------------------------------------------------------------
alter table worker_credentials add column if not exists expiry_date date;

-- ---------------------------------------------------------------------
-- 3. Standing
-- ---------------------------------------------------------------------
alter table water_stations add column if not exists standing text not null default 'applicant';
alter table water_stations add column if not exists standing_since timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'water_stations_standing_check') then
    alter table water_stations add constraint water_stations_standing_check
      check (standing in ('applicant', 'good', 'warning', 'lapsed', 'suspended'));
  end if;
end $$;

create or replace function compliance_grace_days() returns int
language sql stable set search_path = public as $$
  select coalesce((select grace_days from association_settings limit 1), 30);
$$;

-- Re-works one station's accreditation and standing and tells the owner
-- (and, on a lapse, the officers) when the standing changes. Called by the
-- permit trigger and by the daily job.
create or replace function refresh_station_compliance(p_station_id uuid) returns void as $$
declare
  s water_stations%rowtype;
  v_grace int := compliance_grace_days();
  v_all_ok boolean;
  v_expired_any boolean;
  v_expired_past_grace boolean;
  v_standing text;
begin
  select * into s from water_stations where id = p_station_id;
  if not found then
    return;
  end if;

  -- An approved permit counts until it is past expiry + grace.
  select not exists (
    select 1 from permits
     where station_id = p_station_id and is_required
       and (status <> 'approved' or (expiry_date is not null and expiry_date < current_date - v_grace))
  ) into v_all_ok;

  select exists (select 1 from permits where station_id = p_station_id and is_required and status = 'approved'
                   and expiry_date is not null and expiry_date < current_date),
         exists (select 1 from permits where station_id = p_station_id and is_required and status = 'approved'
                   and expiry_date is not null and expiry_date < current_date - v_grace)
    into v_expired_any, v_expired_past_grace;

  if s.accreditation_override_by is null then
    update water_stations
       set is_accredited = v_all_ok,
           accreditation_status = case
             when v_all_ok then 'accredited'
             when accreditation_status = 'accredited' then 'under_review'
             else accreditation_status
           end,
           updated_at = now()
     where id = p_station_id
       and (is_accredited is distinct from v_all_ok
            or (v_all_ok and accreditation_status <> 'accredited')
            or (not v_all_ok and accreditation_status = 'accredited'));
    select * into s from water_stations where id = p_station_id;
  end if;

  v_standing := case
    when not s.is_active or s.accreditation_status = 'suspended' then 'suspended'
    when v_expired_past_grace and s.accreditation_override_by is null then 'lapsed'
    when v_expired_any then 'warning'
    when s.is_accredited then 'good'
    when s.accredited_at is not null then 'warning'
    else 'applicant'
  end;

  if v_standing is distinct from s.standing then
    update water_stations set standing = v_standing, standing_since = now() where id = p_station_id;

    if s.owner_profile_id is not null and v_standing in ('good', 'warning', 'lapsed') then
      insert into notifications (profile_id, category, title, body, station_id)
      values (s.owner_profile_id, 'accreditation',
              case v_standing
                when 'good' then 'Your station is in good standing'
                when 'warning' then 'Action needed: a permit has expired'
                else 'Your accreditation has lapsed'
              end,
              case v_standing
                when 'good' then 'All required permits are current.'
                when 'warning' then 'Upload the renewed permit within ' || v_grace || ' days of its expiry to keep your accreditation.'
                else 'A required permit expired more than ' || v_grace || ' days ago. Your Accredited badge is removed until you upload a valid one.'
              end,
              p_station_id);
    end if;

    if v_standing = 'lapsed' then
      insert into notifications (profile_id, category, title, body, station_id)
      select m.profile_id, 'accreditation', 'Station lapsed: ' || s.station_name,
             'A required permit is past expiry and the grace period.', p_station_id
        from memberships m where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
    end if;
  end if;
end;
$$ language plpgsql security definer set search_path = public;

-- The permit trigger now goes through the same function.
create or replace function recompute_accreditation() returns trigger as $$
begin
  perform refresh_station_compliance(new.station_id);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- A new expiry date (a renewal) or a change to which permits are required
-- also re-works the standing at once; the trigger above fires on status
-- only.
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_refresh_compliance_on_permit_dates') then
    create trigger trg_refresh_compliance_on_permit_dates
      after update of expiry_date, is_required on permits
      for each row execute function recompute_accreditation();
  end if;
end $$;

-- Standing and accreditation are WASA's (or the system's) to set. The
-- daily job runs with no signed-in user, which the guard now allows; no
-- client ever reaches water_stations without one.
create or replace function prevent_owner_self_accreditation() returns trigger as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if not auth_has_role('wasa_admin') then
    if new.is_accredited is distinct from old.is_accredited
       or new.accreditation_status is distinct from old.accreditation_status
       or new.is_colorum_verified is distinct from old.is_colorum_verified
       or new.is_active is distinct from old.is_active
       or new.standing is distinct from old.standing
       or new.standing_since is distinct from old.standing_since then
      raise exception 'Only WASA admin may change accreditation, standing, verification, or active status.';
    end if;
  elsif (new.is_accredited is distinct from old.is_accredited
         or new.accreditation_override_by is distinct from old.accreditation_override_by
         or new.is_active is distinct from old.is_active)
        and auth_linked_to_station(new.id) then
    raise exception 'You are linked to this station, so another officer must decide its accreditation.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- An officer certifying a station by hand, or closing/reopening it, shows
-- in its standing at once rather than at the next daily run. Fires only on
-- those columns, which refresh_station_compliance never writes, so it
-- can't loop.
create or replace function refresh_compliance_on_station_change() returns trigger as $$
begin
  perform refresh_station_compliance(new.id);
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_refresh_compliance_on_station_change') then
    create trigger trg_refresh_compliance_on_station_change
      after update of accreditation_override_by, is_active on water_stations
      for each row execute function refresh_compliance_on_station_change();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. Daily job
-- ---------------------------------------------------------------------
create table if not exists compliance_reminders (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('permit', 'credential')),
  ref_id uuid not null,
  expiry_date date not null,
  threshold text not null check (threshold in ('30', '7', 'expired')),
  sent_at timestamptz not null default now(),
  unique (kind, ref_id, expiry_date, threshold)
);
alter table compliance_reminders enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'compliance_reminders' and policyname = 'compliance_reminders_admin_read') then
    create policy compliance_reminders_admin_read on compliance_reminders for select using (auth_has_role('wasa_admin'));
  end if;
end $$;

create or replace function run_daily_compliance() returns void as $$
declare
  r record;
  v_threshold text;
  v_days int;
  v_label text;
begin
  -- Permits.
  for r in
    select p.id, p.station_id, p.permit_type, p.expiry_date, ws.owner_profile_id, ws.station_name
      from permits p join water_stations ws on ws.id = p.station_id
     where p.is_required and p.status = 'approved' and p.expiry_date is not null
       and p.expiry_date <= current_date + 30 and ws.is_active
  loop
    v_days := r.expiry_date - current_date;
    v_threshold := case when v_days < 0 then 'expired' when v_days <= 7 then '7' else '30' end;
    insert into compliance_reminders (kind, ref_id, expiry_date, threshold)
    values ('permit', r.id, r.expiry_date, v_threshold)
    on conflict do nothing;
    if found and r.owner_profile_id is not null then
      select coalesce(label, initcap(replace(r.permit_type::text, '_', ' '))) into v_label
        from permit_type_labels where permit_type = r.permit_type;
      insert into notifications (profile_id, category, title, body, station_id)
      values (r.owner_profile_id, 'permit',
              case v_threshold
                when 'expired' then coalesce(v_label, 'A permit') || ' has expired'
                else coalesce(v_label, 'A permit') || ' expires in ' || v_days || ' day' || case when v_days = 1 then '' else 's' end
              end,
              case v_threshold
                when 'expired' then 'Upload the renewed permit in the Permit vault within ' || compliance_grace_days()
                                    || ' days to keep your accreditation.'
                else 'Upload the renewal in the Permit vault before ' || to_char(r.expiry_date, 'Mon DD, YYYY') || '.'
              end,
              r.station_id);
    end if;
  end loop;

  -- Driver licences (and any credential with an expiry).
  for r in
    select c.id, c.credential_type, c.expiry_date, w.profile_id as driver_profile, w.full_name, ws.owner_profile_id, ws.id as station_id
      from worker_credentials c
      join workers w on w.id = c.worker_id
      left join water_stations ws on ws.id = w.station_id
     where c.status = 'approved' and c.expiry_date is not null and c.expiry_date <= current_date + 30
  loop
    v_days := r.expiry_date - current_date;
    v_threshold := case when v_days < 0 then 'expired' when v_days <= 7 then '7' else '30' end;
    insert into compliance_reminders (kind, ref_id, expiry_date, threshold)
    values ('credential', r.id, r.expiry_date, v_threshold)
    on conflict do nothing;
    if found then
      insert into notifications (profile_id, category, title, body, station_id)
      select p, 'worker',
             case v_threshold
               when 'expired' then initcap(replace(r.credential_type, '_', ' ')) || ' has expired'
               else initcap(replace(r.credential_type, '_', ' ')) || ' expires in ' || v_days || ' day' || case when v_days = 1 then '' else 's' end
             end,
             coalesce(r.full_name, 'A driver') || ' -- upload the renewed one in the Driver Profile.',
             r.station_id
        from (select r.driver_profile as p union select r.owner_profile_id) t
       where p is not null;
    end if;
  end loop;

  -- Every station's standing, the same clock for all.
  for r in select id from water_stations loop
    perform refresh_station_compliance(r.id);
  end loop;
end;
$$ language plpgsql security definer set search_path = public;

revoke execute on function run_daily_compliance() from public, anon, authenticated;
revoke execute on function refresh_station_compliance(uuid) from public, anon, authenticated;

create extension if not exists pg_cron;

do $$ begin
  if not exists (select 1 from cron.job where jobname = 'gentri-daily-compliance') then
    -- 22:00 UTC is 06:00 in the Philippines.
    perform cron.schedule('gentri-daily-compliance', '0 22 * * *', 'select public.run_daily_compliance()');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Official notices
-- ---------------------------------------------------------------------
create table if not exists notices (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  body text not null check (length(trim(body)) > 0),
  station_id uuid references water_stations(id) on delete cascade,   -- null: every station
  requires_ack boolean not null default true,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists notice_receipts (
  notice_id uuid not null references notices(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  primary key (notice_id, profile_id)
);
alter table notices enable row level security;
alter table notice_receipts enable row level security;

create or replace function auth_owned_station_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from water_stations where owner_profile_id = auth.uid() limit 1;
$$;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'notices' and policyname = 'notices_admin_all') then
    create policy notices_admin_all on notices for all using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notices' and policyname = 'notices_station_read') then
    create policy notices_station_read on notices for select
      using (auth_owned_station_id() is not null and (station_id is null or station_id = auth_owned_station_id()));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notice_receipts' and policyname = 'notice_receipts_admin_read') then
    create policy notice_receipts_admin_read on notice_receipts for select using (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'notice_receipts' and policyname = 'notice_receipts_self_read') then
    create policy notice_receipts_self_read on notice_receipts for select using (profile_id = auth.uid());
  end if;
end $$;

create or replace function send_notice(p_title text, p_body text, p_station_id uuid default null, p_requires_ack boolean default true)
returns uuid as $$
declare
  v_id uuid;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA officers can send official notices.';
  end if;
  insert into notices (title, body, station_id, requires_ack, created_by)
  values (trim(p_title), trim(p_body), p_station_id, p_requires_ack, auth.uid())
  returning id into v_id;

  insert into notifications (profile_id, category, title, body, station_id)
  select ws.owner_profile_id, 'account', 'Official notice from WASA: ' || trim(p_title),
         case when p_requires_ack then 'Please read and acknowledge it in Notices.' else 'Read it in Notices.' end,
         ws.id
    from water_stations ws
   where ws.owner_profile_id is not null and ws.is_active
     and (p_station_id is null or ws.id = p_station_id);
  return v_id;
end;
$$ language plpgsql security definer set search_path = public;

-- Marks a notice read, and acknowledged when [p_acknowledge].
create or replace function mark_notice(p_notice_id uuid, p_acknowledge boolean default false) returns void as $$
begin
  if not exists (select 1 from notices n where n.id = p_notice_id
                  and (n.station_id is null or n.station_id = auth_owned_station_id())
                  and auth_owned_station_id() is not null) then
    raise exception 'Notice not found.';
  end if;
  insert into notice_receipts (notice_id, profile_id, acknowledged_at)
  values (p_notice_id, auth.uid(), case when p_acknowledge then now() end)
  on conflict (notice_id, profile_id) do update
    set acknowledged_at = coalesce(notice_receipts.acknowledged_at, excluded.acknowledged_at);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function send_notice(text, text, uuid, boolean) to authenticated;
grant execute on function mark_notice(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Compliance cases
-- ---------------------------------------------------------------------
create table if not exists compliance_cases (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null references water_stations(id) on delete cascade,
  kind text not null check (kind in ('permit', 'water_test', 'conduct', 'complaint')),
  summary text not null check (length(trim(summary)) > 0),
  evidence text,
  status text not null default 'open' check (status in ('open', 'warning_issued', 'board_action', 'resolved')),
  decision text,
  opened_by uuid references profiles(id) on delete set null,
  decided_by uuid references profiles(id) on delete set null,
  decided_at timestamptz,
  station_response text,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists compliance_cases_station_idx on compliance_cases (station_id, created_at desc);
alter table compliance_cases enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'compliance_cases' and policyname = 'compliance_cases_admin_all') then
    create policy compliance_cases_admin_all on compliance_cases for all
      using (auth_has_role('wasa_admin')) with check (auth_has_role('wasa_admin'));
  end if;
  if not exists (select 1 from pg_policies where tablename = 'compliance_cases' and policyname = 'compliance_cases_owner_read') then
    create policy compliance_cases_owner_read on compliance_cases for select using (station_id = auth_owned_station_id());
  end if;
end $$;

-- Officers deciding a case they're linked to is a conflict, as with permits.
create or replace function guard_compliance_case() returns trigger as $$
begin
  -- Only officers decide cases; the conflict rule is about them. The
  -- station's own written response (respond_to_case) passes through here
  -- too and must not be refused for being "linked" to its own station.
  if auth.uid() is not null and auth_has_role('wasa_admin') and auth_linked_to_station(new.station_id) then
    raise exception 'You are linked to this station, so another officer must handle its case.';
  end if;
  if tg_op = 'INSERT' then
    new.opened_by := coalesce(new.opened_by, auth.uid());
  elsif new.status is distinct from old.status or new.decision is distinct from old.decision then
    new.decided_by := auth.uid();
    new.decided_at := now();
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;
