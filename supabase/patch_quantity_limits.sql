-- Limits the server enforces, not only the customer's order form.
--
-- The app capped an order at 50 jugs, but the station's phone/walk-in order
-- and any direct request took any number (1000 jugs went through). A
-- driver's jug capacity had no cap at all (the test plan says 20). Existing
-- rows are left alone: the rules apply when a value is set or changed.

create or replace function check_order_quantity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.jugs_ordered > 50
     and (tg_op = 'INSERT' or new.jugs_ordered is distinct from old.jugs_ordered) then
    raise exception 'At most 50 jugs per order. For a bigger order, place it in parts or call the station.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_check_order_quantity
  before insert or update of jugs_ordered on orders
  for each row execute function check_order_quantity();

create or replace function check_jug_capacity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.jug_capacity is not null and (new.jug_capacity < 1 or new.jug_capacity > 20)
     and (tg_op = 'INSERT' or new.jug_capacity is distinct from old.jug_capacity) then
    raise exception 'Jug capacity must be between 1 and 20.';
  end if;
  return new;
end;
$$;

create or replace trigger trg_check_jug_capacity
  before insert or update of jug_capacity on workers
  for each row execute function check_jug_capacity();

-- VERIFY: insert of an order with 51 jugs or a driver with capacity 21 is refused.
