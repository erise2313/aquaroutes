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
