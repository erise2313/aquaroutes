-- =====================================================================
-- Jug provenance tracking: closes the gap where jug_ledger_entries was
-- never actually populated by real deliveries -- only by a station
-- owner manually typing a net quantity with no link to what caused it.
-- A customer now declares which station's jug they're returning (if
-- exchanging), the driver confirms/corrects it at delivery, and
-- set_order_status automatically records the resulting inter-station
-- debt, linked to the order that caused it (jug_ledger_entries.related_order_id,
-- which existed but was never populated until now).
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

alter table orders add column if not exists jug_exchange_origin_station_id uuid references water_stations(id);

-- ---- insert_quick_order: customer declares jug origin at order time ----
-- Only stored when the ordering station actually offers jug exchange and
-- the declared origin isn't the ordering station itself (returning your
-- own station's jug needs no ledger entry) -- anything else is silently
-- ignored rather than rejected, since the driver gets a chance to
-- confirm/correct this at delivery anyway.

create or replace function insert_quick_order(
  p_station_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_jugs_ordered int,
  p_water_type text,
  p_subtotal numeric,
  p_delivery_fee numeric,
  p_total_amount numeric,
  p_guest_name text default null,
  p_guest_phone text default null,
  p_client_request_id text default null,
  p_scheduled_for timestamptz default null,
  p_jug_type text default null,
  p_jug_exchange_origin_station_id uuid default null
) returns uuid as $$
declare
  new_order_id uuid;
  v_is_active boolean;
  v_accepts_new_orders boolean;
  v_offers_jug_exchange boolean;
  v_origin uuid;
begin
  if p_client_request_id is not null then
    select id into new_order_id from orders where client_request_id = p_client_request_id;
    if new_order_id is not null then
      return new_order_id;
    end if;
  end if;

  select is_active, accepts_new_orders, offers_jug_exchange
    into v_is_active, v_accepts_new_orders, v_offers_jug_exchange
    from water_stations where id = p_station_id;
  if v_is_active is null or not v_is_active or not coalesce(v_accepts_new_orders, true) then
    raise exception 'This station is not currently accepting orders.';
  end if;

  v_origin := case
    when p_jug_exchange_origin_station_id is not null
      and p_jug_exchange_origin_station_id <> p_station_id
      and coalesce(v_offers_jug_exchange, false)
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
    p_subtotal, p_delivery_fee, p_total_amount,
    p_guest_phone, p_client_request_id, p_scheduled_for,
    v_origin
  ) returning id into new_order_id;

  return new_order_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---- set_order_status: driver confirms/corrects jug origin, and the ----
-- ---- resulting jug_ledger_entries row is written automatically       ----
-- Re-declared (not just CREATE OR REPLACE) with two new trailing params
-- -- unlike insert_quick_order's history, existing callers of this
-- function pass different SUBSETS of its named parameters (e.g.
-- unassignOrder passes only p_order_id/p_new_status), so simply adding
-- an overload would make every such call ambiguous between the old and
-- new signatures ("could not choose the best candidate function").
-- Dropping the old one first keeps there being exactly one candidate.

drop function if exists set_order_status(uuid, order_status, uuid, text, int, boolean);

create function set_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_driver_worker_id uuid default null,
  p_guest_phone text default null,
  p_empty_jugs_returned int default null,
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

  -- Customer / guest: cancel their own order only, before it's out for delivery.
  if (auth.uid() is not null and o.customer_profile_id = auth.uid())
     or (auth.uid() is null and p_guest_phone is not null and o.guest_phone = p_guest_phone) then
    if o.status not in ('pending', 'assigned') or p_new_status <> 'cancelled' then
      raise exception 'You can only cancel an order before it is out for delivery.';
    end if;
    update orders set status = 'cancelled' where id = p_order_id;
    return;
  end if;

  -- Station owner / WASA admin: assign, cancel, unassign.
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

  -- Driver: start/complete their own assigned delivery only.
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

      -- Automatic jug-provenance capture: closes the gap where this table
      -- was only ever populated by a manual, order-disconnected guess.
      -- jug_type is guarded against anything other than the two known
      -- container shapes since orders.jug_type is free text (mirrors
      -- water_type's convention) while jug_ledger_entries.jug_type is the
      -- enum -- an unexpected value here should never block completing a
      -- delivery.
      if o.jug_exchange_origin_station_id is not null
         and o.jug_exchange_origin_station_id <> o.station_id
         and o.jug_type in ('slim_5gal', 'round_5gal')
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
