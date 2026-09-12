-- =====================================================================
-- patch_customer_addresses.sql
--
-- Customers had to drop a pin on the map for every single order, even
-- when ordering to the same house every week. This stores the places a
-- customer orders to, labelled, with one default that the order form
-- pre-selects.
--
-- Only the customer can see or change their own; the address only reaches
-- a station through the order they place (orders.delivery_location),
-- exactly as before.
-- =====================================================================

create table if not exists customer_addresses (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 40),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  notes text check (notes is null or char_length(notes) <= 200),
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists customer_addresses_profile_idx on customer_addresses (profile_id, created_at);

-- At most one default each, enforced rather than hoped for.
create unique index if not exists customer_addresses_one_default
  on customer_addresses (profile_id) where is_default;

alter table customer_addresses enable row level security;
revoke all on customer_addresses from anon;

drop policy if exists customer_addresses_self_all on customer_addresses;
create policy customer_addresses_self_all on customer_addresses
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Marking one default clears the previous one, so saving never fails on
-- the unique index above.
create or replace function enforce_single_default_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_default then
    update customer_addresses
       set is_default = false
     where profile_id = new.profile_id and id <> new.id and is_default;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_single_default_address on customer_addresses;
create trigger trg_enforce_single_default_address
  before insert or update on customer_addresses
  for each row execute function enforce_single_default_address();
