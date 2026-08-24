-- WASA Bulletin & Floor Price Policy Board: publicly readable announcements
-- and price floors (guards against price dumping). Bulletins are mostly
-- admin-authored (Announcements/Price Changes) but station_owner/driver may
-- post Community Event/General Discussion posts too -- see the
-- bulletins_member_insert policy in 0009_rls.sql.

create table floor_prices (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  water_type text not null,
  min_price_per_jug numeric(10,2) not null,
  effective_date date not null default current_date,
  set_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  -- One floor price per water type per association -- BulletinService
  -- upserts against this (bulletin_editor_screen.dart's "Set Price") so
  -- re-setting a price for the same water type updates it in place
  -- instead of accumulating duplicate rows.
  unique (association_id, water_type)
);

create index floor_prices_association_idx on floor_prices (association_id);

create type bulletin_category as enum ('announcement', 'price_change', 'event', 'discussion');

create table bulletins (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  category bulletin_category not null default 'discussion',
  title text not null,
  body text not null,
  is_pinned boolean not null default false,
  posted_by uuid not null references profiles(id),
  -- Denormalized at post time (not joined at read time) so the feed doesn't
  -- need to embed through memberships/water_stations per card. A later
  -- name change won't retroactively update old posts -- acceptable here.
  author_name text not null,
  author_role app_role not null,
  author_station_name text,
  -- Optional photo attached at post-creation time. Uploaded to the
  -- bulletin-images bucket under a client-generated path BEFORE the row is
  -- inserted (not updated afterward), since non-admin posters only have an
  -- INSERT policy on bulletins, not UPDATE.
  image_url text,
  created_at timestamptz not null default now()
);

create index bulletins_association_idx on bulletins (association_id);
create index bulletins_category_idx on bulletins (category);

-- Lightweight "acknowledge" reaction -- one per (bulletin, profile), no
-- reaction types/kinds, just a tap toggle. Publicly readable counts (via
-- the view below) so guests can see engagement without logging in; only an
-- authenticated user may add/remove their own reaction (0009_rls.sql).
create table bulletin_reactions (
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bulletin_id, profile_id)
);

create index bulletin_reactions_bulletin_idx on bulletin_reactions (bulletin_id);

create view bulletin_reaction_counts as
  select bulletin_id, count(*) as reaction_count
  from bulletin_reactions
  group by bulletin_id;

grant select on bulletin_reaction_counts to anon, authenticated;

-- Public bucket for bulletin post photos -- any authenticated
-- station_owner/driver/wasa_admin (i.e. anyone allowed to post at all) may
-- upload; reads go through the public CDN URL.
insert into storage.buckets (id, name, public)
  values ('bulletin-images', 'bulletin-images', true)
  on conflict (id) do nothing;

-- Neither bulletins_admin_insert nor bulletins_member_insert (0009_rls.sql)
-- constrain posted_by/author_role, so without this a station_owner/driver
-- (who only need to satisfy the category check) could insert a post with
-- posted_by set to an arbitrary profile and author_role='wasa_admin',
-- visually impersonating an official WASA announcement. This confirms
-- posted_by is really the caller and author_role matches a role they
-- actually, currently hold.
create or replace function validate_bulletin_author() returns trigger as $$
begin
  if new.posted_by <> auth.uid() then
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

create trigger trg_validate_bulletin_author
  before insert on bulletins
  for each row execute function validate_bulletin_author();

-- ---------------------------------------------------------------------
-- Floor price enforcement. floor_prices is opt-in per water_type -- a
-- station charging below the association's floor for any type it offers
-- gets blocked at the point price_per_jug or offered_water_types changes,
-- rather than silently allowed and only visible as a policy document. If
-- no floor has been set yet for any of the station's offered types, the
-- check is skipped entirely (nothing to enforce yet).
-- ---------------------------------------------------------------------
create or replace function enforce_floor_price() returns trigger as $$
declare
  v_floor numeric(10,2);
begin
  select max(min_price_per_jug) into v_floor
    from floor_prices
    where association_id = new.association_id
      and water_type = any(new.offered_water_types);

  if v_floor is not null and new.price_per_jug < v_floor then
    raise exception 'price_per_jug (%) is below the association floor price (%) for one or more offered water types.', new.price_per_jug, v_floor;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_enforce_floor_price
  before insert or update of price_per_jug, offered_water_types on water_stations
  for each row execute function enforce_floor_price();

-- ---------------------------------------------------------------------
-- Guest order lookup (B2). No account exists for a guest order, so the
-- phone number doubles as the access credential -- returns a row only when
-- it matches guest_phone on the order, so knowing an order ID alone isn't
-- enough to read someone else's delivery details.
-- ---------------------------------------------------------------------
create or replace function lookup_guest_order(p_order_id uuid, p_guest_phone text)
returns table (
  id uuid, station_name text, status order_status, jugs_ordered int,
  water_type text, total_amount numeric, created_at timestamptz
) as $$
begin
  return query
    select o.id, s.station_name, o.status, o.jugs_ordered, o.water_type, o.total_amount, o.created_at
    from orders o
    join water_stations s on s.id = o.station_id
    where o.id = p_order_id and o.guest_phone = p_guest_phone;
end;
$$ language plpgsql security definer set search_path = public;
