-- =====================================================================
-- Incremental patch: deferred audit fixes (Part A) + lighter feature
-- recommendations (Part B) from the follow-up QA/feature-gap report.
-- Additive/corrective to your existing schema -- no data loss. Paste into
-- the Supabase SQL Editor and run once. Safe to re-run.
--
-- Part A (deferred fixes):
--   A1  workers.station_id FK: cascade -> set null (deleting a station no
--       longer wipes a worker's identity/incident/credential history).
--   A2  Floor price is now enforced when a station's price_per_jug or
--       offered_water_types changes.
--   A3  bulletin-images storage policy now scoped to the poster's own
--       folder, not just their role.
--   A4  permits.reviewed_by / worker_credentials.reviewed_by /
--       worker_incidents.resolved_by: restrict -> set null.
--   A5  New indexes on bulletins.category, worker_credentials.status,
--       permits.status.
-- Part B (feature additions):
--   B1  bulletin_reactions table + public read-count view.
--   B2  lookup_guest_order() RPC for phone-verified guest order tracking.
--   B3  permits.expiry_date column for renewal reminders.
-- =====================================================================


-- ---------------------------------------------------------------------
-- A1: workers.station_id -- cascade -> set null
-- ---------------------------------------------------------------------
alter table workers drop constraint if exists workers_station_id_fkey;
alter table workers add constraint workers_station_id_fkey
  foreign key (station_id) references water_stations(id) on delete set null;

-- ---------------------------------------------------------------------
-- A4: profile-review columns -- restrict -> set null
-- ---------------------------------------------------------------------
alter table permits drop constraint if exists permits_reviewed_by_fkey;
alter table permits add constraint permits_reviewed_by_fkey
  foreign key (reviewed_by) references profiles(id) on delete set null;

alter table worker_credentials drop constraint if exists worker_credentials_reviewed_by_fkey;
alter table worker_credentials add constraint worker_credentials_reviewed_by_fkey
  foreign key (reviewed_by) references profiles(id) on delete set null;

alter table worker_incidents drop constraint if exists worker_incidents_resolved_by_fkey;
alter table worker_incidents add constraint worker_incidents_resolved_by_fkey
  foreign key (resolved_by) references profiles(id) on delete set null;

-- ---------------------------------------------------------------------
-- A5: indexes
-- ---------------------------------------------------------------------
create index if not exists bulletins_category_idx on bulletins (category);
create index if not exists worker_credentials_status_idx on worker_credentials (status);
create index if not exists permits_status_idx on permits (status);

-- ---------------------------------------------------------------------
-- B3: permit renewal date
-- ---------------------------------------------------------------------
alter table permits add column if not exists expiry_date date;

-- ---------------------------------------------------------------------
-- A2: floor price enforcement
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

drop trigger if exists trg_enforce_floor_price on water_stations;
create trigger trg_enforce_floor_price
  before insert or update of price_per_jug, offered_water_types on water_stations
  for each row execute function enforce_floor_price();

-- ---------------------------------------------------------------------
-- B2: guest order lookup
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

-- ---------------------------------------------------------------------
-- B1: bulletin reactions
-- ---------------------------------------------------------------------
create table if not exists bulletin_reactions (
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bulletin_id, profile_id)
);

create index if not exists bulletin_reactions_bulletin_idx on bulletin_reactions (bulletin_id);

drop view if exists bulletin_reaction_counts;
create view bulletin_reaction_counts as
  select bulletin_id, count(*) as reaction_count
  from bulletin_reactions
  group by bulletin_id;

grant select on bulletin_reaction_counts to anon, authenticated;

alter table bulletin_reactions enable row level security;

drop policy if exists bulletin_reactions_public_read on bulletin_reactions;
create policy bulletin_reactions_public_read on bulletin_reactions for select
  using (true);

drop policy if exists bulletin_reactions_self_insert on bulletin_reactions;
create policy bulletin_reactions_self_insert on bulletin_reactions for insert
  with check (profile_id = auth.uid());

drop policy if exists bulletin_reactions_self_delete on bulletin_reactions;
create policy bulletin_reactions_self_delete on bulletin_reactions for delete
  using (profile_id = auth.uid());

-- ---------------------------------------------------------------------
-- A3: bulletin-images path scoping
-- NOTE: this tightens the write policy to require the first path segment
-- to be the uploader's own profile ID. If you have existing bulletin
-- images uploaded under the OLD path convention ({profile_id}_{timestamp}/...
-- -- the folder segment included a trailing suffix, not a bare uuid), this
-- new check still reads those objects fine (bucket is public / read is
-- unrestricted) but a future overwrite of that exact path would fail the
-- uuid cast. This only affects new uploads going forward, which now use
-- the corrected {profile_id}/{timestamp}_image.{ext} convention.
-- ---------------------------------------------------------------------
drop policy if exists bulletin_images_poster_write on storage.objects;
create policy bulletin_images_poster_write on storage.objects for insert
  with check (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );
