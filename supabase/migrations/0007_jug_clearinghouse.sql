-- Inter-Station Jug Clearinghouse: tracks which station is holding how many
-- of another station's 5-gallon Slim/Round jugs, and settles those balances
-- only once the *receiving* (owed) station confirms.

create type jug_type as enum ('slim_5gal', 'round_5gal');

-- Append-only ledger. Positive quantity = holder_station gained jugs
-- belonging to owner_station; negative = holder_station returned/settled them.
create table jug_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  holder_station_id uuid not null references water_stations(id),
  owner_station_id uuid not null references water_stations(id),
  jug_type jug_type not null,
  quantity int not null check (quantity <> 0),
  related_order_id uuid references orders(id),
  recorded_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  check (holder_station_id <> owner_station_id)
);

create index jug_ledger_holder_idx on jug_ledger_entries (holder_station_id);
create index jug_ledger_owner_idx on jug_ledger_entries (owner_station_id);

-- Net balance per station pair per jug type.
create view jug_balances as
  select holder_station_id, owner_station_id, jug_type, sum(quantity) as net_qty
  from jug_ledger_entries
  group by holder_station_id, owner_station_id, jug_type
  having sum(quantity) <> 0;

create type settlement_status as enum ('proposed', 'confirmed', 'rejected');

create table jug_settlements (
  id uuid primary key default gen_random_uuid(),
  holder_station_id uuid not null references water_stations(id),
  owner_station_id uuid not null references water_stations(id),
  jug_type jug_type not null,
  quantity int not null check (quantity > 0),
  status settlement_status not null default 'proposed',
  proposed_by uuid not null references profiles(id),
  confirmed_by uuid references profiles(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create index jug_settlements_holder_idx on jug_settlements (holder_station_id);
create index jug_settlements_owner_idx on jug_settlements (owner_station_id);

-- Only the RECEIVING station (owner_station -- the one being repaid) may
-- confirm a settlement. Confirming writes an offsetting ledger entry.
create or replace function confirm_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  -- Explicit NULL-safe check -- see owner_remove_worker (0005_workers.sql)
  -- for why `<> auth_station_id()` alone is not safe when the caller has
  -- no station membership.
  if auth_station_id() is null or auth_station_id() <> s.owner_station_id then
    raise exception 'only the owning/receiving station may confirm this settlement';
  end if;

  insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by)
    values (s.holder_station_id, s.owner_station_id, s.jug_type, -s.quantity, auth.uid());

  update jug_settlements
    set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;

-- Rejecting a settlement only the receiving station (or an admin) should be able to do.
create or replace function reject_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if (auth_station_id() is null or auth_station_id() <> s.owner_station_id) and not auth_has_role('wasa_admin') then
    raise exception 'only the owning/receiving station or a WASA admin may reject this settlement';
  end if;

  update jug_settlements set status = 'rejected' where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;
