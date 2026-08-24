-- =====================================================================
-- GENTRI WASA -- SECOND TEST ACCOUNT SET (demo/testing only)
-- =====================================================================
-- A completely separate 4-role set (1 admin, 1 station owner, 1 driver,
-- 1 customer) with its own distinct emails/invite code -- running this
-- does NOT touch or overwrite the accounts created by
-- seed_test_accounts.sql (admin@/owner1@/owner2@/driver1@/driver2@/
-- customer1@gentriwasa.test). Use this if you want a fresh, untouched
-- set of logins for a presentation without resetting whatever state
-- your first set is currently in.
--
-- The station owned here is pre-accredited + colorum-verified and the
-- driver is pre-cleared, same shortcuts as the first seed script, so
-- everything is immediately demoable with no upload/review wait.
-- DO NOT run this against a production project with real users.
--
-- Run supabase/reset_and_rebuild.sql FIRST if you haven't already.
-- Then paste this whole file into the Supabase SQL Editor and run it.
-- Safe to re-run -- it cleans up its own 4 accounts first, same
-- idempotency pattern as seed_test_accounts.sql.
-- =====================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  owner_id uuid := gen_random_uuid();
  driver_id uuid := gen_random_uuid();
  customer_id uuid := gen_random_uuid();
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_station_id uuid := gen_random_uuid();
  barangay_id uuid;
  test_emails text[] := array[
    'admin2@gentriwasa.test', 'owner3@gentriwasa.test',
    'driver3@gentriwasa.test', 'customer2@gentriwasa.test'
  ];
begin

  -- -------------------------------------------------------------------
  -- 0. Idempotency cleanup, scoped only to these 4 emails -- see
  --    seed_test_accounts.sql for why this order (children before the
  --    auth.users row that cascades the rest).
  -- -------------------------------------------------------------------
  delete from workers where profile_id in (select id from auth.users where email = any(test_emails));
  delete from water_stations where owner_profile_id in (select id from auth.users where email = any(test_emails));
  delete from memberships where profile_id in (select id from auth.users where email = any(test_emails));
  delete from auth.users where email = any(test_emails);

  -- -------------------------------------------------------------------
  -- 1. Auth users (email/password, pre-confirmed -- no email sent).
  -- -------------------------------------------------------------------
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
     'admin2@gentriwasa.test', crypt('Admin123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"WASA Admin Two"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', owner_id, 'authenticated', 'authenticated',
     'owner3@gentriwasa.test', crypt('Owner123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Ramon Villanueva"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', driver_id, 'authenticated', 'authenticated',
     'driver3@gentriwasa.test', crypt('Driver123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Carlos Mendoza"}',
     now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', customer_id, 'authenticated', 'authenticated',
     'customer2@gentriwasa.test', crypt('Customer123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Grace Villareal"}',
     now(), now(), '', '', '', '');

  -- Required by current Supabase Auth for email/password sign-in to work.
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), admin_id, admin_id::text, jsonb_build_object('sub', admin_id::text, 'email', 'admin2@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), owner_id, owner_id::text, jsonb_build_object('sub', owner_id::text, 'email', 'owner3@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), driver_id, driver_id::text, jsonb_build_object('sub', driver_id::text, 'email', 'driver3@gentriwasa.test'), 'email', now(), now(), now()),
    (gen_random_uuid(), customer_id, customer_id::text, jsonb_build_object('sub', customer_id::text, 'email', 'customer2@gentriwasa.test'), 'email', now(), now(), now());

  -- -------------------------------------------------------------------
  -- 2. WASA admin membership (no station_id -- association-wide).
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role)
  values (admin_id, v_association_id, 'wasa_admin');

  -- -------------------------------------------------------------------
  -- 3. One station, already accredited + colorum-verified.
  -- -------------------------------------------------------------------
  select id into barangay_id from barangays where association_id = v_association_id and name = 'San Francisco';

  insert into water_stations (
    id, association_id, owner_profile_id, barangay_id, invite_code,
    station_name, station_address, latitude, longitude,
    price_per_jug, delivery_fee, offered_water_types,
    is_accredited, accreditation_status, is_colorum_verified
  ) values (
    v_station_id, v_association_id, owner_id, barangay_id,
    'SANFRA1',
    'San Francisco Pure Water Station',
    'San Francisco, General Trias, Cavite',
    14.3690, 120.8820,
    24.00, 18.00,
    array['purified', 'mineral', 'alkaline'],
    true, 'accredited', true
  );

  insert into memberships (profile_id, association_id, role, station_id) values
    (owner_id, v_association_id, 'station_owner', v_station_id);

  update permits
    set status = 'approved', reviewed_by = admin_id, reviewed_at = now()
    where station_id = v_station_id;

  -- -------------------------------------------------------------------
  -- 4. One driver, pre-cleared (skips pending_clearance).
  -- -------------------------------------------------------------------
  insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity, clearance_status) values
    (v_station_id, driver_id, 'Carlos Mendoza', '09171234503', 'DEF9012', 18, 'cleared');

  insert into memberships (profile_id, association_id, role, station_id) values
    (driver_id, v_association_id, 'driver', v_station_id);

  -- -------------------------------------------------------------------
  -- 5. One customer account (public_consumer, no station).
  -- -------------------------------------------------------------------
  insert into memberships (profile_id, association_id, role, station_id) values
    (customer_id, v_association_id, 'public_consumer', null);

end $$;
