-- Water stations: extends the old single-tenant water_stations table with
-- association scoping, water-type offerings, and WASA accreditation state.

create table water_stations (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id),
  owner_profile_id uuid not null references profiles(id),
  barangay_id uuid references barangays(id),
  invite_code text not null unique,
  station_name text not null,
  station_address text not null,
  latitude double precision not null,
  longitude double precision not null,
  price_per_jug numeric(10,2) not null default 0,
  delivery_fee numeric(10,2) not null default 0,
  -- Storefront photo shown on the public map/quick-order screens.
  photo_url text,
  -- e.g. {'purified','mineral','alkaline'}
  offered_water_types text[] not null default '{}',
  -- WASA has confirmed this station is a legitimate, licensed operator
  -- (the "colorum" verification seal shown on the public map).
  is_colorum_verified boolean not null default false,
  -- Flipped true only once every required permit row is approved
  -- (see 0004_permits.sql triggers).
  is_accredited boolean not null default false,
  accreditation_status text not null default 'pending'
    check (accreditation_status in ('pending','under_review','accredited','rejected','suspended')),
  -- Admin-only deactivation switch, orthogonal to accreditation -- a station
  -- can be fully accredited yet deactivated (e.g. temporarily closed), or
  -- vice versa. Hides the station from public_stations/ordering (0009_rls.sql)
  -- without deleting any of its history.
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index water_stations_association_idx on water_stations (association_id);
create index water_stations_owner_idx on water_stations (owner_profile_id);
create index water_stations_barangay_idx on water_stations (barangay_id);

-- Public bucket (storefront photos are meant to be publicly visible) --
-- path convention {station_id}/photo.{ext}. Write access restricted to the
-- owning station (0009_rls.sql); reads go through the public CDN URL
-- since the bucket itself is public, no select policy needed.
insert into storage.buckets (id, name, public)
  values ('station-photos', 'station-photos', true)
  on conflict (id) do nothing;
