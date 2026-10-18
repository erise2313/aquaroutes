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
