-- =====================================================================
-- Two lapsed stations (demo/testing only).
--
--   owner4@gentriwasa.test  Owner123!  Rosalinda Santos -- Santiago Pure Water
--       water quality test report expired 45 days ago
--   owner5@gentriwasa.test  Owner123!  Ernesto Villanueva -- Pasong Kawayan Aqua Hub
--       business permit expired 60 days ago
--
-- A station lapses when a required permit is more than the grace period
-- (30 days) past its expiry. Both are built the way it happens for real:
-- every required permit approved (the station is accredited and gets the
-- seal), then one permit's expiry passes the grace period. The standing
-- check then marks them LAPSED: still listed and still orderable, but the
-- Accredited badge is gone and "Accredited only" hides them
-- (refresh_station_compliance).
--
-- Additive and idempotent: an owner whose email already exists is left
-- untouched. Run after seed_sample_products.sql. Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_id uuid;
  v_station uuid;
  v_barangay uuid;
  acct record;
begin
  for acct in
    select * from (values
      ('owner4@gentriwasa.test', 'Rosalinda Santos',   '09171230021', 'Santiago Pure Water',     'Santiago',
       'SANTGO1', 'STAFFSG', 14.3640, 120.8930, 'water_quality_test_report', 45, 26.00,
       'Purok 3, Santiago', 'Beside the barangay health center'),
      ('owner5@gentriwasa.test', 'Ernesto Villanueva', '09171230022', 'Pasong Kawayan Aqua Hub', 'Pasong Kawayan I',
       'PKAWAY1', 'STAFFPK', 14.3520, 120.8620, 'business_permit', 60, 24.00,
       'Blk 5 Lot 12, Pasong Kawayan I', 'Across the chapel')
    ) as t(email, full_name, phone, station_name, barangay, invite_code, staff_code, lat, lng,
           expired_permit, days_expired, price, street, landmark)
  loop
    if exists (select 1 from auth.users where email = acct.email) then
      continue;
    end if;

    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      acct.email, crypt('Owner123!', gen_salt('bf')),
      now(), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', acct.full_name),
      now() - interval '14 months', now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', acct.email), 'email', now(), now(), now());
    update profiles set phone_number = acct.phone, privacy_consented_at = now(), privacy_notice_version = 'seed'
     where id = v_id;

    select id into v_barangay from barangays where association_id = v_association_id and name = acct.barangay;
    v_station := gen_random_uuid();
    -- sync_required_permits creates the eight required permits, missing.
    insert into water_stations (
      id, association_id, owner_profile_id, barangay_id, invite_code, staff_invite_code,
      station_name, station_address, street, city, landmark, latitude, longitude,
      price_per_jug, delivery_fee, offered_water_types, created_at
    ) values (
      v_station, v_association_id, v_id, v_barangay, acct.invite_code, acct.staff_code,
      acct.station_name, acct.street || ', ' || acct.barangay || ', General Trias, Cavite',
      acct.street, 'General Trias', acct.landmark, acct.lat, acct.lng,
      acct.price, 15.00, array['purified'], now() - interval '14 months'
    );
    insert into memberships (profile_id, association_id, role, station_id)
    values (v_id, v_association_id, 'station_owner', v_station);

    insert into station_products (station_id, water_type, container_code, kind, price) values
      (v_station, 'purified', 'slim_5gal', 'refill', acct.price),
      (v_station, 'purified', 'round_5gal', 'refill', acct.price)
    on conflict (station_id, water_type, container_code, kind) do nothing;
    perform sync_station_from_products(v_station);

    -- 1. Accredited: every required permit approved and current. Only an
    --    officer may approve, and the SQL Editor has no signed-in officer,
    --    so the guard is off for exactly these statements.
    alter table permits disable trigger trg_prevent_owner_self_permit_approval;
    update permits
       set status = 'approved',
           uploaded_at = now() - interval '13 months',
           reviewed_at = now() - interval '13 months',
           expiry_date = (current_date + interval '6 months')::date
     where station_id = v_station and is_required;

    -- 2. One permit runs out and the grace period passes: lapsed.
    update permits
       set expiry_date = current_date - acct.days_expired
     where station_id = v_station and permit_type = acct.expired_permit::permit_type;
    alter table permits enable trigger trg_prevent_owner_self_permit_approval;

    -- Accredited about a year ago, not today.
    update water_stations set accredited_at = now() - interval '13 months' where id = v_station;
    perform refresh_station_compliance(v_station);
  end loop;
end $$;

-- VERIFY -- both should read: lapsed, not accredited, listed.
select ws.station_code, ws.station_name, ws.standing, ws.is_accredited, ws.is_colorum_verified,
       exists (select 1 from public_stations p where p.id = ws.id) as listed,
       (select string_agg(p.permit_type::text || ' expired ' || p.expiry_date, ', ')
          from permits p where p.station_id = ws.id and p.expiry_date < current_date) as expired
  from water_stations ws
 where ws.station_name in ('Santiago Pure Water', 'Pasong Kawayan Aqua Hub');
