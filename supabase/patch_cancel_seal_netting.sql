-- =====================================================================
-- patch_cancel_seal_netting.sql -- 19 Oct 2026
--
--   1. Cancelling an order needs a reason, from the customer or the
--      station, and only while it is pending or assigned: once the driver
--      has set out ("out for delivery") nobody can cancel it. Everyone
--      affected is told the reason.
--   2. A station that becomes accredited gets the verification seal at the
--      same time, so it shows in the public directory without a second step.
--   3. Jug balances are netted per pair of stations: 14 jugs one way and 9
--      the other read as one balance of 5. Settlements are checked against
--      the net figure.
--
-- Idempotent; no drops. Mirrored into reset_and_rebuild.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cancel with a reason
-- ---------------------------------------------------------------------
alter table orders add column if not exists cancel_reason text;
alter table orders add column if not exists cancelled_by text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'orders_cancelled_by_check') then
    alter table orders add constraint orders_cancelled_by_check
      check (cancelled_by is null or cancelled_by in ('customer', 'station', 'wasa'));
  end if;
end $$;

create or replace function cancel_order(p_order_id uuid, p_reason text) returns void as $$
declare
  o orders%rowtype;
  v_by text;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Say why the order is being cancelled.';
  end if;
  select * into o from orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found.';
  end if;

  if auth.uid() is not null and o.customer_profile_id = auth.uid() then
    v_by := 'customer';
  elsif exists (select 1 from water_stations where id = o.station_id and owner_profile_id = auth.uid())
     or (auth_staff_station_id() is not null and auth_staff_station_id() = o.station_id) then
    v_by := 'station';
  elsif auth_has_role('wasa_admin') then
    v_by := 'wasa';
  else
    raise exception 'Not authorized to cancel this order.';
  end if;

  if o.status = 'active' then
    raise exception 'The driver has already left with this order, so it can no longer be cancelled.';
  elsif o.status not in ('pending', 'assigned') then
    raise exception 'This order is already %, so it can''t be cancelled.',
      case o.status when 'done' then 'delivered' else o.status::text end;
  end if;

  perform set_config('gentri.trusted_order_change', 'on', true);
  update orders set status = 'cancelled', cancel_reason = left(trim(p_reason), 300), cancelled_by = v_by
   where id = p_order_id;
  perform set_config('gentri.trusted_order_change', 'off', true);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function cancel_order(uuid, text) to authenticated;

-- Notifications now carry the cancel reason, and a driver whose delivery
-- is cancelled is told too.
create or replace function notify_order_event() returns trigger
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_owner uuid;
  v_station_name text;
  v_driver_profile uuid;
  v_line text;
  v_failed boolean;
  v_reason text;
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
  v_reason := case when new.cancel_reason is not null then ' · Reason: ' || new.cancel_reason else '' end;

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
    if new.customer_profile_id is not null and not (new.status = 'cancelled' and new.cancelled_by = 'customer') then
      insert into notifications (profile_id, category, title, body, order_id, station_id)
      values (
        new.customer_profile_id, 'order',
        case new.status
          when 'assigned' then 'A driver is on the way'
          when 'active' then 'Your order is out for delivery'
          when 'done' then 'Order delivered'
          when 'cancelled' then case new.cancelled_by
                                  when 'station' then 'Order cancelled by the station'
                                  when 'wasa' then 'Order cancelled by WASA'
                                  else 'Order cancelled' end
          else 'Order updated'
        end,
        coalesce(v_station_name, 'Your station') || ' · ' || v_line
          || case when new.status = 'cancelled' then v_reason else '' end,
        new.id, new.station_id);
    end if;

    if new.status = 'cancelled' then
      -- The station hears about a cancellation it didn't make itself.
      if new.cancelled_by is distinct from 'station' then
        insert into notifications (profile_id, category, title, body, order_id, station_id)
        select p, 'order',
               case new.cancelled_by
                 when 'wasa' then 'Order cancelled by WASA'
                 when 'customer' then 'Order cancelled by the customer'
                 else 'Order cancelled' end,
               v_line || ' · ' || peso_text(new.total_amount) || v_reason, new.id, new.station_id
          from (select v_owner as p
                union
                select m.profile_id from memberships m
                 where m.station_id = new.station_id and m.role = 'station_staff' and m.status = 'active') t
         where p is not null;
      end if;
      -- A driver who was holding it no longer needs to go.
      if old.driver_worker_id is not null then
        select profile_id into v_driver_profile from workers where id = old.driver_worker_id;
        if v_driver_profile is not null then
          insert into notifications (profile_id, category, title, body, order_id, station_id)
          values (v_driver_profile, 'order', 'Delivery cancelled', v_line || v_reason, new.id, new.station_id);
        end if;
      end if;
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
$function$;

-- ---------------------------------------------------------------------
-- 2. Accreditation brings the seal
-- ---------------------------------------------------------------------
create or replace function seal_on_accreditation() returns trigger as $$
begin
  if new.is_accredited and not coalesce(old.is_accredited, false) then
    new.is_colorum_verified := true;
  end if;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_a_seal_on_accreditation') then
    -- Named to run before the officer-only guard on the same table.
    create trigger trg_a_seal_on_accreditation before update of is_accredited on water_stations
      for each row execute function seal_on_accreditation();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Netted jug balances
-- ---------------------------------------------------------------------
-- security_invoker: each station still sees only balances it is part of
-- (jug_ledger_entries' own read rules apply).
create or replace view jug_balances with (security_invoker = true) as
  select case when net > 0 then s1 else s2 end as holder_station_id,
         case when net > 0 then s2 else s1 end as owner_station_id,
         jug_type,
         abs(net) as net_qty
    from (
      select least(holder_station_id, owner_station_id) as s1,
             greatest(holder_station_id, owner_station_id) as s2,
             jug_type,
             sum(case when holder_station_id < owner_station_id then quantity else -quantity end) as net
        from jug_ledger_entries
       group by 1, 2, 3
    ) t
   where net <> 0;

-- How many of p_owner's jugs p_holder holds, net of jugs going the other way.
create or replace function jug_net_owed(p_holder uuid, p_owner uuid, p_type jug_type) returns int as $$
  select coalesce(sum(case when holder_station_id = p_holder then quantity else -quantity end), 0)::int
    from jug_ledger_entries
   where jug_type = p_type
     and ((holder_station_id = p_holder and owner_station_id = p_owner)
       or (holder_station_id = p_owner and owner_station_id = p_holder));
$$ language sql stable security definer set search_path = public;

create or replace function check_jug_settlement_proposal() returns trigger as $$
declare
  v_owed int;
begin
  if new.quantity is null or new.quantity < 1 then
    raise exception 'Enter how many jugs you are returning.';
  end if;
  v_owed := jug_net_owed(new.holder_station_id, new.owner_station_id, new.jug_type);
  if new.quantity > v_owed then
    raise exception 'You hold % of their jugs of this type (after netting), so you can settle at most that many.', greatest(v_owed, 0);
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function confirm_jug_settlement(p_settlement_id uuid) returns void
language plpgsql security definer set search_path to 'public'
as $function$
declare
  s jug_settlements%rowtype;
  v_owed int;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if auth_station_id() is null or auth_station_id() <> s.owner_station_id then
    raise exception 'only the owning/receiving station may confirm this settlement';
  end if;

  v_owed := jug_net_owed(s.holder_station_id, s.owner_station_id, s.jug_type);

  if s.quantity > v_owed then
    raise exception 'This settlement (% jugs) exceeds the current outstanding balance (% jugs).', s.quantity, greatest(v_owed, 0);
  end if;

  insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by)
    values (s.holder_station_id, s.owner_station_id, s.jug_type, -s.quantity, auth.uid());

  update jug_settlements
    set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    where id = p_settlement_id;
end;
$function$;
