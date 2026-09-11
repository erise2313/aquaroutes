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
