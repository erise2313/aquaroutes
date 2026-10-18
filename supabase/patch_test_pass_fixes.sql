-- =====================================================================
-- patch_test_pass_fixes.sql -- bugs found running the test cases against
-- the live database (18 Oct 2026). Idempotent; no drops.
-- =====================================================================

-- GTW-APP-259: a driver leaving a station while holding a delivery failed
-- outright -- releasing the order back to the station tripped
-- protect_order_financial_fields, which only lets owners and officers
-- change an order's driver. The release is checked here, so it is marked as
-- a trusted change (as driver_switch_station already does).
create or replace function driver_leave_station() returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare v_worker_id uuid;
begin
  select id into v_worker_id from workers where profile_id = auth.uid();

  if v_worker_id is null then
    raise exception 'No worker record found for this account.';
  end if;

  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'pending', driver_worker_id = null
    where driver_worker_id = v_worker_id and status in ('assigned', 'active');
  perform set_config('gentri.trusted_order_change', 'off', true);

  update workers set station_id = null, updated_at = now() where id = v_worker_id;
  update memberships set station_id = null where profile_id = auth.uid() and role = 'driver';
  update worker_station_history set status = 'left', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = v_worker_id and status = 'active';
end;
$function$;

-- GTW-APP-196 / WEB-254: only cleared drivers take deliveries. Pending
-- drivers (new, or back to pending after an incident) were assignable --
-- only flagged ones were refused.
create or replace function public.set_order_status(p_order_id uuid, p_new_status order_status, p_driver_worker_id uuid default null::uuid, p_guest_phone text default null::text, p_empty_jugs_returned integer default null::integer, p_payment_collected boolean default null::boolean, p_jug_exchange_origin_station_id uuid default null::uuid, p_no_jug_exchange boolean default false)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
      if v_new_driver_clearance is distinct from 'cleared' then
        raise exception 'This driver is not cleared by WASA yet and cannot be assigned deliveries.';
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
$function$;

-- GTW-WEB-225: a permit or worker credential could be rejected with no
-- reason (the dialog accepted a blank one and so did the table), leaving
-- the owner or driver nothing to fix.
create or replace function require_rejection_reason() returns trigger as $$
begin
  if new.status = 'rejected' and new.status is distinct from old.status
     and coalesce(trim(new.rejection_reason), '') = '' then
    raise exception 'Give a reason for the rejection -- it is sent to them so they know what to fix.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_permits_require_reason') then
    create trigger trg_permits_require_reason before update on permits
      for each row execute function require_rejection_reason();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_credentials_require_reason') then
    create trigger trg_credentials_require_reason before update on worker_credentials
      for each row execute function require_rejection_reason();
  end if;
end $$;

-- GTW-WEB-179: the form requires an incident description, but the table
-- accepted a blank one -- and an incident puts a driver back to pending.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'worker_incidents_description_present') then
    alter table worker_incidents add constraint worker_incidents_description_present
      check (length(trim(description)) > 0) not valid;
  end if;
end $$;

-- GTW-WEB-205 (and spoofing): a post's author name and station name were
-- taken from the app as sent, so a modified app could post as "WASA" or as
-- another station; and a member could pin their own post. The database now
-- fills both names from the account itself and only officers may pin.
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

  select coalesce(nullif(trim(full_name), ''), 'Member') into new.author_name
    from profiles where id = auth.uid();
  new.author_name := coalesce(new.author_name, 'Member');
  if auth_has_role('wasa_admin') then
    new.author_station_name := null;
  else
    new.is_pinned := false;
    select ws.station_name into new.author_station_name
      from memberships m join water_stations ws on ws.id = m.station_id
     where m.profile_id = auth.uid() and m.role = new.author_role and m.status = 'active'
     limit 1;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- GTW-WEB-260 / APP-027: the forms refuse a blank post title or comment;
-- the tables now do too.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'bulletins_title_present') then
    alter table bulletins add constraint bulletins_title_present check (length(trim(title)) > 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'bulletin_comments_body_present') then
    alter table bulletin_comments add constraint bulletin_comments_body_present check (length(trim(body)) > 0) not valid;
  end if;
end $$;

-- GTW-WEB-161 / 163: a settlement for more jugs than are outstanding (or
-- for none) was accepted when proposed and only refused when the other
-- station tried to confirm it. Refused when proposed now, with the balance.
create or replace function check_jug_settlement_proposal() returns trigger as $$
declare
  v_owed int;
begin
  if new.quantity is null or new.quantity < 1 then
    raise exception 'Enter how many jugs you are returning.';
  end if;
  select coalesce(sum(quantity), 0) into v_owed
    from jug_ledger_entries
   where holder_station_id = new.holder_station_id
     and owner_station_id = new.owner_station_id
     and jug_type = new.jug_type;
  if new.quantity > v_owed then
    raise exception 'You hold % of their jugs of this type, so you can settle at most that many.', v_owed;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_check_jug_settlement_proposal') then
    create trigger trg_check_jug_settlement_proposal before insert on jug_settlements
      for each row execute function check_jug_settlement_proposal();
  end if;
end $$;

-- Clearinghouse integrity: either station in a pair could insert any
-- ledger entry -- a negative one erases its own debt, and recorded_by and
-- related_order_id could name anyone. A station may now only record a
-- positive transfer, as itself, not tied to an order. Balances go down only
-- through a confirmed settlement (confirm_jug_settlement) or an officer;
-- order-linked entries come from set_order_status.
alter policy jug_ledger_involved_insert on jug_ledger_entries
  with check (
    ((holder_station_id in (select id from water_stations where owner_profile_id = auth.uid()))
      or (owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())))
    and quantity > 0
    and recorded_by = auth.uid()
    and related_order_id is null
  );

-- ---------------------------------------------------------------------
-- Direct-write guards (security sweep). The app changes orders, drivers,
-- permits and stations through checked functions (set_order_status,
-- insert_quick_order, station_create_order, driver_switch_station, ...).
-- The table policies were wider than that, so a modified app could:
--   * create orders in any customer's name for its station,
--   * clear its own flagged driver, or add a "cleared" driver,
--   * delete its permits so its station counted as fully accredited,
--   * change an order's status directly as its driver.
-- A write straight from a signed-in user (current_user 'authenticated',
-- not inside a function or another trigger) now may only touch what the
-- screens actually edit. Officers keep full access.
-- ---------------------------------------------------------------------
create or replace function is_direct_member_write() returns boolean as $$
  select current_user in ('authenticated', 'anon')
     and pg_trigger_depth() <= 1
     and not auth_has_role('wasa_admin');
$$ language sql stable set search_path = public;  -- invoker: must see the caller's role

create or replace function guard_direct_order_write() returns trigger as $$
begin
  if is_direct_member_write() then
    raise exception 'Orders can only be placed and changed through the order screens.';
  end if;
  return coalesce(new, old);
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_worker_write() returns trigger as $$
begin
  if not is_direct_member_write() then
    return coalesce(new, old);
  end if;
  if tg_op <> 'UPDATE' then
    raise exception 'Drivers join and leave a station with an invite code, not directly.';
  end if;
  -- Name, phone, plate and capacity only; clearance is WASA's, the station
  -- changes through join/leave.
  if (to_jsonb(new) - array['full_name', 'phone_number', 'vehicle_plate', 'jug_capacity', 'role_title', 'updated_at'])
     is distinct from (to_jsonb(old) - array['full_name', 'phone_number', 'vehicle_plate', 'jug_capacity', 'role_title', 'updated_at']) then
    raise exception 'Only WASA can change a driver''s clearance or station.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_permit_write() returns trigger as $$
begin
  if not is_direct_member_write() then
    return coalesce(new, old);
  end if;
  if tg_op <> 'UPDATE' then
    raise exception 'Permits are set by the association; upload a document to the one listed.';
  end if;
  -- An upload: the file, when, and back to review.
  if (to_jsonb(new) - array['storage_path', 'uploaded_at', 'status'])
     is distinct from (to_jsonb(old) - array['storage_path', 'uploaded_at', 'status'])
     or (new.status is distinct from old.status and new.status <> 'pending_review') then
    raise exception 'Only WASA can change which permits are required or decide them.';
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

create or replace function guard_direct_station_delete() returns trigger as $$
begin
  if is_direct_member_write() then
    raise exception 'A station is closed by WASA, not deleted.';
  end if;
  return old;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_order_write') then
    create trigger trg_guard_direct_order_write before insert or update or delete on orders
      for each row execute function guard_direct_order_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_worker_write') then
    create trigger trg_guard_direct_worker_write before insert or update or delete on workers
      for each row execute function guard_direct_worker_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_permit_write') then
    create trigger trg_guard_direct_permit_write before insert or update or delete on permits
      for each row execute function guard_direct_permit_write();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_guard_direct_station_delete') then
    create trigger trg_guard_direct_station_delete before delete on water_stations
      for each row execute function guard_direct_station_delete();
  end if;
end $$;

-- A driver's "Save profile" (name, phone, plate, capacity) silently saved
-- nothing: there was no policy letting drivers update their own record.
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'workers' and policyname = 'workers_self_update') then
    create policy workers_self_update on workers for update
      using (profile_id = auth.uid()) with check (profile_id = auth.uid());
  end if;
end $$;

-- Trash: a deleted product was listed as just its water type ("mineral").
-- It now reads like the product list ("Mineral, Round 5-gal").
create or replace function move_to_trash() returns trigger as $$
declare
  r jsonb := to_jsonb(old);
  v_batch uuid;
  v_child boolean := pg_trigger_depth() > 1;
  v_label text;
begin
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
  if tg_table_name = 'station_products' then
    select initcap(r->>'water_type') || ', ' || coalesce(ct.label, r->>'container_code')
           || case when r->>'kind' = 'new_container' then ' (new container)' else '' end
      into v_label
      from (select 1) x left join container_types ct on ct.code = r->>'container_code';
  else
    v_label := coalesce(r->>'title', r->>'question', r->>'label', r->>'name',
                        r->>'body', r->>'comment', r->>'content', r->>'water_type');
  end if;
  insert into trash (batch_id, is_child, table_name, row_data, kind, label, station_id, deleted_by)
  values (v_batch, v_child, tg_table_name, r, trash_kind(tg_table_name), left(v_label, 120),
          nullif(r->>'station_id', '')::uuid, auth.uid());
  return old;
end;
$$ language plpgsql security definer set search_path = public;

-- Security advisor: fixed search_path on the Trash label helper.
alter function trash_kind(text) set search_path = public;
