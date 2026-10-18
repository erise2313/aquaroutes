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

-- =====================================================================
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when ok then 'ok' else 'NOT APPLIED' end as result from (values
  ('permit validity set', exists (select 1 from permit_type_labels where permit_type = 'water_quality_test_report' and validity_months = 1)),
  ('default expiry trigger', exists (select 1 from pg_trigger where tgname = 'trg_permit_default_expiry')),
  ('licence expiry column', exists (select 1 from information_schema.columns where table_name = 'worker_credentials' and column_name = 'expiry_date')),
  ('every station has a standing', not exists (select 1 from water_stations where standing is null)),
  ('daily job scheduled', exists (select 1 from cron.job where jobname = 'gentri-daily-compliance')),
  ('notices tables', exists (select 1 from information_schema.tables where table_name = 'notice_receipts')),
  ('compliance cases', exists (select 1 from information_schema.tables where table_name = 'compliance_cases'))
) as t(item, ok);
