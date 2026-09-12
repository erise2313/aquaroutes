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
