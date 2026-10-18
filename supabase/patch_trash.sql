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

-- ---------------------------------------------------------------------
-- VERIFY
-- ---------------------------------------------------------------------
select check_name, ok from (values
  ('trash table', exists (select 1 from information_schema.tables where table_name = 'trash')),
  ('trash triggers', (select count(*) from pg_trigger where tgname like 'trg_trash_%') = 13),
  ('purge job', exists (select 1 from cron.job where jobname = 'gentri-purge-trash'))
) as v(check_name, ok);
