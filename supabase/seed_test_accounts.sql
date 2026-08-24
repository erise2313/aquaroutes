-- =====================================================================
-- AquaRoute / GENTRI WASA -- TEST ACCOUNT SEEDING (demo/testing only)
-- =====================================================================
-- Creates ready-to-use login accounts so you don't have to register
-- through the app UI: 1 WASA admin, 2 station owners (each with a
-- station that already has a location set), 2 drivers (each assigned
-- to one of those stations), and 1 customer account. All permits for
-- the two demo stations are marked 'approved' and both stations are
-- forced accredited + colorum-verified, so they show up fully
-- functional on the public map and owner portal immediately --
-- bypassing the normal "upload and wait for WASA review" flow purely
-- for ease of demoing.
--
-- For a lean 4-role presentation flow (admin / owner / driver /
-- customer) you only need admin@, owner1@, driver1@, and customer1@ --
-- owner2@/driver2@ are there if you also want to demo Hire Check
-- (cross-station worker lookup) against a second station.
-- DO NOT run this against a production project with real users.
--
-- Coordinates below are approximate placeholders within General Trias,
-- Cavite for demo purposes -- not surveyed/verified real addresses.
--
-- Run supabase/reset_and_rebuild.sql FIRST if you haven't already.
-- Then paste this whole file into the Supabase SQL Editor and run it.
-- =====================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  owner1_id uuid := gen_random_uuid();
  owner2_id uuid := gen_random_uuid();
  driver1_id uuid := gen_random_uuid();
  driver2_id uuid := gen_random_uuid();
  customer1_id uuid := gen_random_uuid();
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  station1_id uuid := gen_random_uuid();
  station2_id uuid := gen_random_uuid();
  barangay1_id uuid;
  barangay2_id uuid;
  test_emails text[] := array[
    'admin@gentriwasa.test', 'owner1@gentriwasa.test', 'owner2@gentriwasa.test',
    'driver1@gentriwasa.test', 'driver2@gentriwasa.test', 'customer1@gentriwasa.test'
  ];
  v_old_profile_ids uuid[];
  v_old_station_ids uuid[];
begin

  -- -------------------------------------------------------------------
  -- 0. Idempotency: if this script was already run before (or these
  -- accounts picked up other activity in the meantime -- floor prices,
  -- bulletin posts, orders, jug ledger entries, etc., all reference
  -- profiles/stations with no cascade), re-running would collide on the
  -- unique email constraint and/or fail on a foreign key. Clean up every
  -- table that references these profiles or their stations first, in
  -- FK-safe order, before removing the profiles/stations/auth users
  -- themselves.
  -- -------------------------------------------------------------------
  select array_agg(id) into v_old_profile_ids from auth.users where email = any(test_emails);
  select array_agg(id) into v_old_station_ids from water_stations where owner_profile_id = any(v_old_profile_ids);

  if v_old_profile_ids is not null then
    delete from bulletin_reactions where profile_id = any(v_old_profile_ids);
    delete from bulletin_comments where profile_id = any(v_old_profile_ids);
    delete from reviews where profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from jug_settlements where proposed_by = any(v_old_profile_ids) or confirmed_by = any(v_old_profile_ids)
      or holder_station_id = any(v_old_station_ids) or owner_station_id = any(v_old_station_ids);
    delete from jug_ledger_entries where recorded_by = any(v_old_profile_ids)
      or holder_station_id = any(v_old_station_ids) or owner_station_id = any(v_old_station_ids);
    delete from orders where customer_profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from bulletins where posted_by = any(v_old_profile_ids);
    delete from floor_prices where set_by = any(v_old_profile_ids);
    delete from resources where uploaded_by = any(v_old_profile_ids);
    delete from events where created_by = any(v_old_profile_ids);
    delete from worker_incidents where reported_by_profile_id = any(v_old_profile_ids) or resolved_by = any(v_old_profile_ids);
    delete from worker_station_history where ended_by_profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from memberships where profile_id = any(v_old_profile_ids);
    delete from workers where profile_id = any(v_old_profile_ids) or station_id = any(v_old_station_ids);
    delete from water_stations where owner_profile_id = any(v_old_profile_ids);
    delete from auth.users where id = any(v_old_profile_ids);
  end if;

  -- -------------------------------------------------------------------
  -- 1. Auth users (email/password, pre-confirmed -- no email sent).
  --    The handle_new_auth_user trigger (0001_core_identity.sql) auto-
  --    creates each matching `profiles` row from raw_user_meta_data.
  -- -------------------------------------------------------------------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
     'admin@gentriwasa.test', crypt('Admin123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"WASA Admin"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', owner1_id, 'authenticated', 'authenticated',
     'owner1@gentriwasa.test', crypt('Owner123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Juan Dela Cruz"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', owner2_id, 'authenticated', 'authenticated',
     'owner2@gentriwasa.test', crypt('Owner123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Maria Santos"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', driver1_id, 'authenticated', 'authenticated',
     'driver1@gentriwasa.test', crypt('Driver123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Pedro Reyes"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', driver2_id, 'authenticated', 'authenticated',
     'driver2@gentriwasa.test', crypt('Driver123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Ana Cruz"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', customer1_id, 'authenticated', 'authenticated',
     'customer1@gentriwasa.test', crypt('Customer123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Liza Fernandez"}',
     now(), now(), '', '', '', '');

  -- Required by current Supabase Auth for email/password sign-in to work.
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), admin_id, admin_id::text, jsonb_build_object('sub', admin_id::text, 'email', 'admin@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), owner1_id, owner1_id::text, jsonb_build_object('sub', owner1_id::text, 'email', 'owner1@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), owner2_id, owner2_id::text, jsonb_build_object('sub', owner2_id::text, 'email', 'owner2@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), driver1_id, driver1_id::text, jsonb_build_object('sub', driver1_id::text, 'email', 'driver1@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), driver2_id, driver2_id::text, jsonb_build_object('sub', driver2_id::text, 'email', 'driver2@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), customer1_id, customer1_id::text, jsonb_build_object('sub', customer1_id::text, 'email', 'customer1@gentriwasa.test'), 'email', now(), now(), now());

  -- -------------------------------------------------------------------
  -- 2. WASA admin membership (no station_id -- association-wide).
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role)
  values (admin_id, v_association_id, 'wasa_admin');

  -- -------------------------------------------------------------------
  -- 3. Two stations, each with a location already set.
  -- -------------------------------------------------------------------
  select id into barangay1_id from barangays where association_id = v_association_id and name = 'Buenavista I';
  select id into barangay2_id from barangays where association_id = v_association_id and name = 'Navarro';

  insert into water_stations (
    id, association_id, owner_profile_id, barangay_id, invite_code,
    station_name, station_address, latitude, longitude,
    price_per_jug, delivery_fee, offered_water_types
  ) values (
    station1_id, v_association_id, owner1_id, barangay1_id,
    'BUENAV1',
    'Buenavista Water Refilling Station',
    'Buenavista I, General Trias, Cavite',
    14.3745, 120.8790,
    25.00, 20.00,
    array['purified', 'alkaline']
  ), (
    station2_id, v_association_id, owner2_id, barangay2_id,
    'NAVSPR1',
    'Navarro Springs Water Station',
    'Navarro, General Trias, Cavite',
    14.3958, 120.8875,
    22.00, 15.00,
    array['purified', 'mineral']
  );

  insert into memberships (profile_id, association_id, role, station_id) values
    (owner1_id, v_association_id, 'station_owner', station1_id),
    (owner2_id, v_association_id, 'station_owner', station2_id);

  -- -------------------------------------------------------------------
  -- 4. Force both demo stations fully accredited + colorum-verified,
  --    and mark every permit 'approved' -- skips the normal upload/
  --    review wait entirely, per your ask for ease of demoing.
  -- -------------------------------------------------------------------
  update water_stations
    set is_accredited = true, accreditation_status = 'accredited', is_colorum_verified = true
    where id in (station1_id, station2_id);

  update permits
    set status = 'approved', reviewed_by = admin_id, reviewed_at = now()
    where station_id in (station1_id, station2_id);

  -- -------------------------------------------------------------------
  -- 5. Two drivers, one per station, pre-cleared (skips pending_clearance).
  -- -------------------------------------------------------------------
  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity, clearance_status) values
    (station1_id, driver1_id, 'Pedro Reyes', '09171234501', 'ABC1234', 20, 'cleared'),
    (station2_id, driver2_id, 'Ana Cruz', '09171234502', 'XYZ5678', 15, 'cleared');

  insert into memberships (profile_id, association_id, role, station_id) values
    (driver1_id, v_association_id, 'driver', station1_id),
    (driver2_id, v_association_id, 'driver', station2_id);

  -- -------------------------------------------------------------------
  -- 6. One customer account (public_consumer, no station) -- lets you
  --    skip live-registering a customer during a demo if you'd rather
  --    just log straight in and place an order.
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role, station_id) values
    (customer1_id, v_association_id, 'public_consumer', null);

end $$;
