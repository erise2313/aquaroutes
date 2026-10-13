-- Favourite stations: a customer's own shortlist of member stations.
--
-- Purely a per-customer preference -- it grants no access to anything and is
-- never visible to the station. The directory pins favourites above the
-- distance-sorted remainder, so a customer who already has a supplier keeps
-- it at the top without having to search for it each time.
--
-- Guests have no row here at all: the star is hidden when signed out rather
-- than kept in local storage, so there is one source of truth and nothing to
-- reconcile at sign-in.

create table favorite_stations (
  profile_id uuid not null references profiles(id) on delete cascade,
  station_id uuid not null references water_stations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (profile_id, station_id)
);

-- The only read path is "all favourites for the signed-in customer".
create index favorite_stations_profile_idx on favorite_stations (profile_id);

alter table favorite_stations enable row level security;

-- One policy covers every verb: a row is yours or it is not. `with check`
-- mirrors `using` so a customer cannot insert a favourite on someone else's
-- behalf.
create policy favorite_stations_self on favorite_stations for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());
