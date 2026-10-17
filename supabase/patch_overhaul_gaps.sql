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

-- =====================================================================
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when present then 'ok' else 'MISSING' end as result from (values
  ('owner_regenerate_invite_code', exists (select 1 from pg_proc where proname = 'owner_regenerate_invite_code')),
  ('incidents_self_read policy', exists (select 1 from pg_policies where policyname = 'incidents_self_read')),
  ('profiles.privacy_consented_at', exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'privacy_consented_at')),
  ('driver_report_failed_delivery', exists (select 1 from pg_proc where proname = 'driver_report_failed_delivery')),
  ('bulletin_reports table', exists (select 1 from information_schema.tables where table_name = 'bulletin_reports')),
  ('driver_submit_appeal', exists (select 1 from pg_proc where proname = 'driver_submit_appeal')),
  ('audit_log table', exists (select 1 from information_schema.tables where table_name = 'audit_log')),
  ('web_content_revisions table', exists (select 1 from information_schema.tables where table_name = 'web_content_revisions'))
) as t(item, present);
