-- Enable RLS on every table and add explicit per-role policies. This is the
-- real security boundary for the 4-role model (wasa_admin, station_owner,
-- driver, public_consumer) -- client-side role routing in the Flutter app is
-- UX convenience only from here on.
--
-- Fixes the most severe bug found in the old app: driver_management.dart's
-- realtime stream had no station filter at all, so any station owner could
-- see every driver system-wide. RLS makes that structurally impossible even
-- if a client-side filter is ever dropped again.

alter table profiles enable row level security;
alter table memberships enable row level security;
alter table water_stations enable row level security;
alter table permits enable row level security;
alter table workers enable row level security;
alter table worker_incidents enable row level security;
alter table worker_station_history enable row level security;
alter table worker_credentials enable row level security;
alter table orders enable row level security;
alter table driver_states enable row level security;
alter table jug_ledger_entries enable row level security;
alter table jug_settlements enable row level security;
alter table floor_prices enable row level security;
alter table bulletins enable row level security;
alter table bulletin_reactions enable row level security;

-- ---------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------
create policy profiles_self_read on profiles for select
  using (id = auth.uid());
create policy profiles_self_update on profiles for update
  using (id = auth.uid());
create policy profiles_admin_read on profiles for select
  using (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- memberships
-- ---------------------------------------------------------------------
create policy memberships_self_read on memberships for select
  using (profile_id = auth.uid());
create policy memberships_admin_all on memberships for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- water_stations
-- Public/anon access is NOT granted on this table directly (it carries
-- owner_profile_id and other non-public columns) -- see the public_stations
-- view below instead.
-- ---------------------------------------------------------------------
-- Deliberately no owner-INSERT policy: station creation is RPC-only, via
-- register_station_owner() (0003_memberships.sql), which is SECURITY
-- DEFINER and bypasses RLS. This closes the hole where any authenticated
-- user (even with no station_owner membership) could previously insert an
-- arbitrary water_stations row and instantly own it.
-- Gated by auth_has_role('station_owner') in addition to ownership -- not
-- just owner_profile_id = auth.uid() -- so a suspended owner (membership
-- status flipped away from 'active' by a WASA admin) actually loses access
-- to their own station row too, not just to RPC-gated actions.
create policy stations_owner_select on water_stations for select
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_owner_update on water_stations for update
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'))
  with check (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_owner_delete on water_stations for delete
  using (owner_profile_id = auth.uid() and auth_has_role('station_owner'));
create policy stations_admin_all on water_stations for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));
create policy stations_driver_read on water_stations for select
  using (id = auth_station_id());

-- barangay_name added for the website's Stations directory filter
-- (screens/web/stations_directory_screen.dart) -- a left join since
-- barangay_id is nullable on water_stations.
create view public_stations as
  select ws.id, ws.station_name, ws.station_address, ws.latitude, ws.longitude,
         ws.price_per_jug, ws.delivery_fee, ws.offered_water_types, ws.photo_url,
         ws.is_colorum_verified, ws.is_accredited, b.name as barangay_name
  from water_stations ws
  left join barangays b on b.id = ws.barangay_id
  where ws.is_colorum_verified = true and ws.is_active = true;

grant select on public_stations to anon, authenticated;

-- ---------------------------------------------------------------------
-- permits
-- ---------------------------------------------------------------------
create policy permits_owner on permits for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy permits_admin on permits for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- workers
-- ---------------------------------------------------------------------
create policy workers_owner on workers for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy workers_self_read on workers for select
  using (profile_id = auth.uid());
create policy workers_admin on workers for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- worker_incidents
-- Station owners may file/read incidents for their own workers; only a
-- WASA admin may resolve (confirm/dismiss) one.
-- ---------------------------------------------------------------------
create policy incidents_owner_read on worker_incidents for select
  using (worker_id in (
    select w.id from workers w
    join water_stations s on s.id = w.station_id
    where s.owner_profile_id = auth.uid()
  ));
create policy incidents_owner_insert on worker_incidents for insert
  with check (
    reported_by_profile_id = auth.uid()
    and worker_id in (
      select w.id from workers w
      join water_stations s on s.id = w.station_id
      where s.owner_profile_id = auth.uid()
    )
  );
create policy incidents_admin_all on worker_incidents for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- worker_station_history
-- Conservative direct-table access only (self / worker's current station
-- owner / admin) -- cross-station Hire Check reads go exclusively through
-- the hire_check_station_history() security-definer RPC (0005_workers.sql),
-- never raw table access, as defense in depth.
-- ---------------------------------------------------------------------
create policy history_self_read on worker_station_history for select
  using (worker_id in (select id from workers where profile_id = auth.uid()));
create policy history_current_owner_read on worker_station_history for select
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy history_admin_read on worker_station_history for select
  using (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- worker_credentials
-- Worker (self) manages their own uploads; the worker's current station
-- owner may read the row (status only -- the storage bucket policy below
-- separately ensures owners can't fetch the actual document, only WASA
-- admin and the worker themselves can); admin reviews/approves.
-- ---------------------------------------------------------------------
create policy worker_credentials_self on worker_credentials for all
  using (worker_id in (select id from workers where profile_id = auth.uid()))
  with check (worker_id in (select id from workers where profile_id = auth.uid()));
create policy worker_credentials_owner_read on worker_credentials for select
  using (worker_id in (
    select w.id from workers w
    join water_stations s on s.id = w.station_id
    where s.owner_profile_id = auth.uid()
  ));
create policy worker_credentials_admin on worker_credentials for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- orders
-- Station owners see/manage their own station's orders. Drivers see/update
-- orders for their assigned station. Anonymous/public consumers may only
-- INSERT a guest order (no customer_profile_id), never read others' orders.
-- Signed-in customers may read their own past orders.
-- ---------------------------------------------------------------------
create policy orders_owner_all on orders for all
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()))
  with check (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy orders_driver_read on orders for select
  using (station_id = auth_station_id());
create policy orders_driver_update on orders for update
  using (station_id = auth_station_id());
create policy orders_customer_read on orders for select
  using (customer_profile_id = auth.uid());
create policy orders_public_insert on orders for insert
  with check (customer_profile_id is null and guest_name is not null);
create policy orders_authenticated_insert on orders for insert
  with check (customer_profile_id = auth.uid());
create policy orders_admin_read on orders for select
  using (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- driver_states
-- A driver may only write their own row; a station owner may read their own
-- station's driver states; admin reads all. This is the direct fix for the
-- driver_management.dart data-leak bug.
-- ---------------------------------------------------------------------
create policy driver_states_self on driver_states for all
  using (worker_id in (select id from workers where profile_id = auth.uid()))
  with check (worker_id in (select id from workers where profile_id = auth.uid()));
create policy driver_states_owner_read on driver_states for select
  using (station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy driver_states_admin_read on driver_states for select
  using (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- jug_ledger_entries / jug_settlements
-- Either station involved in a ledger entry/settlement may read it; only
-- the holder station may propose a settlement; confirm/reject are enforced
-- inside the confirm_jug_settlement()/reject_jug_settlement() functions
-- (security definer), not by table policy, since they need to write an
-- offsetting ledger row atomically with the status update.
-- ---------------------------------------------------------------------
create policy jug_ledger_involved_read on jug_ledger_entries for select
  using (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_ledger_involved_insert on jug_ledger_entries for insert
  with check (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_ledger_admin on jug_ledger_entries for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

create policy jug_settlements_involved_read on jug_settlements for select
  using (
    holder_station_id in (select id from water_stations where owner_profile_id = auth.uid())
    or owner_station_id in (select id from water_stations where owner_profile_id = auth.uid())
  );
create policy jug_settlements_propose on jug_settlements for insert
  with check (holder_station_id in (select id from water_stations where owner_profile_id = auth.uid()));
create policy jug_settlements_admin on jug_settlements for all
  using (auth_has_role('wasa_admin'))
  with check (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- bulletins / floor_prices
-- Publicly readable (no login required). wasa_admin may post/edit/delete
-- any category. station_owner/driver may only post the two community
-- categories (event/discussion) -- Announcements and Price Changes stay
-- admin-authoritative.
-- ---------------------------------------------------------------------
create policy bulletins_public_read on bulletins for select
  using (true);
create policy bulletins_admin_insert on bulletins for insert
  with check (auth_has_role('wasa_admin') and posted_by = auth.uid());
create policy bulletins_member_insert on bulletins for insert
  with check (
    category in ('event', 'discussion')
    and (auth_has_role('station_owner') or auth_has_role('driver'))
    and posted_by = auth.uid()
  );
create policy bulletins_admin_update on bulletins for update
  using (auth_has_role('wasa_admin'));
create policy bulletins_admin_delete on bulletins for delete
  using (auth_has_role('wasa_admin'));

create policy floor_prices_public_read on floor_prices for select
  using (true);
create policy floor_prices_admin_insert on floor_prices for insert
  with check (auth_has_role('wasa_admin'));
create policy floor_prices_admin_update on floor_prices for update
  using (auth_has_role('wasa_admin'));
create policy floor_prices_admin_delete on floor_prices for delete
  using (auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- bulletin_reactions
-- Counts are publicly readable (guests can see engagement); only the
-- reacting user may add/remove their own reaction row.
-- ---------------------------------------------------------------------
create policy bulletin_reactions_public_read on bulletin_reactions for select
  using (true);
create policy bulletin_reactions_self_insert on bulletin_reactions for insert
  with check (profile_id = auth.uid());
create policy bulletin_reactions_self_delete on bulletin_reactions for delete
  using (profile_id = auth.uid());

-- ---------------------------------------------------------------------
-- storage: permit-documents bucket
-- Path convention: {station_id}/{permit_type}.{ext} -- station owners may
-- read/write only their own station's folder; admins may read all.
-- ---------------------------------------------------------------------
create policy permit_docs_owner_all on storage.objects for all
  using (
    bucket_id = 'permit-documents'
    and (storage.foldername(name))[1]::uuid in (
      select id from water_stations where owner_profile_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'permit-documents'
    and (storage.foldername(name))[1]::uuid in (
      select id from water_stations where owner_profile_id = auth.uid()
    )
  );
create policy permit_docs_admin_read on storage.objects for select
  using (bucket_id = 'permit-documents' and auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- storage: worker-credentials bucket
-- Path convention: {worker_id}/{credential_type}.{ext} -- unlike station
-- permits, personal ID documents are NOT owner-visible: only the worker
-- themselves and wasa_admin can read/write the actual file. Owners only
-- ever see the credential *status* via the worker_credentials table row.
-- ---------------------------------------------------------------------
create policy worker_credentials_self_all on storage.objects for all
  using (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (
      select id from workers where profile_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'worker-credentials'
    and (storage.foldername(name))[1]::uuid in (
      select id from workers where profile_id = auth.uid()
    )
  );
create policy worker_credentials_admin_read on storage.objects for select
  using (bucket_id = 'worker-credentials' and auth_has_role('wasa_admin'));

-- ---------------------------------------------------------------------
-- storage: avatars / station-photos / bulletin-images (all public buckets
-- -- reads go through the public CDN URL, so only write access needs a
-- policy here).
-- ---------------------------------------------------------------------
create policy avatars_self_write on storage.objects for all
  using (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid())
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1]::uuid = auth.uid());

create policy station_photos_owner_write on storage.objects for all
  using (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  )
  with check (
    bucket_id = 'station-photos'
    and (storage.foldername(name))[1]::uuid in (select id from water_stations where owner_profile_id = auth.uid())
  );

-- Path convention: {profile_id}/{filename} (PhotoService.uploadBulletinImage) --
-- scoped to the poster's own folder, matching avatars/station-photos, so a
-- poster can only write into their own path, not an arbitrary one.
create policy bulletin_images_poster_write on storage.objects for insert
  with check (
    bucket_id = 'bulletin-images'
    and (storage.foldername(name))[1]::uuid = auth.uid()
    and (auth_has_role('station_owner') or auth_has_role('driver') or auth_has_role('wasa_admin'))
  );
