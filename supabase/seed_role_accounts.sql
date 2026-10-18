-- =====================================================================
-- More test accounts, one for each situation the test cases need that
-- seed_test_accounts.sql does not cover (demo/testing only).
--
--   admin2@gentriwasa.test     Admin123!     second WASA officer
--   driver3@gentriwasa.test    Driver123!    cleared driver, Buenavista
--   driver4@gentriwasa.test    Driver123!    cleared driver, Navarro Springs
--   customer2@gentriwasa.test  Customer123!  second customer
--   suspended@gentriwasa.test  Customer123!  customer whose account is suspended
--   owner3@gentriwasa.test     Owner123!     owner of a station not yet accredited
--   superadmin1@gentriwasa.test Admin123!    WASA super admin (association president)
--   superadmin2@gentriwasa.test Admin123!    WASA super admin (secretary)
--   staff1@gentriwasa.test     Staff123!     station staff (dispatcher), Buenavista
--
-- Why each one:
--   * admin2 -- the Users list shows officers now; with two, an officer can
--     see the other and confirm they cannot suspend themselves.
--   * driver3/driver4 -- seed_demo_gaps.sql flags driver1, and driver2 was
--     flagged in testing, so neither seeded station had a driver that could
--     be assigned an order. These two are cleared, credentials approved.
--   * customer2 -- checks that one customer cannot see another's orders or
--     follow their driver.
--   * suspended -- signing in shows the "account suspended" screen; the
--     server also refuses their orders.
--   * superadmin1/2 -- the two super admins (patch_roles_governance.sql):
--     manage officers, transfer stations, association settings. Two, so
--     neither can be locked out by the other leaving.
--   * staff1 -- a dispatcher at Buenavista: orders, drivers, tracking only.
--   * owner3 -- a station at the start of the process: permits waiting to
--     be uploaded, not accredited, not on the public map. Walks the whole
--     accreditation flow (Permit vault -> Admin Permits -> accredited).
--
-- Additive and idempotent: an account whose email already exists is left
-- untouched, and nothing is deleted. Run after seed_test_accounts.sql
-- (driver3/driver4 join owner1's and owner2's stations). Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_station1 uuid;
  v_station2 uuid;
  v_station3 uuid;
  v_barangay uuid;
  v_id uuid;
  acct record;
begin
  select ws.id into v_station1 from water_stations ws join auth.users u on u.id = ws.owner_profile_id
   where u.email = 'owner1@gentriwasa.test';
  select ws.id into v_station2 from water_stations ws join auth.users u on u.id = ws.owner_profile_id
   where u.email = 'owner2@gentriwasa.test';
  if v_station1 is null or v_station2 is null then
    raise exception 'Run seed_test_accounts.sql first: owner1''s and owner2''s stations are needed.';
  end if;

  for acct in
    select * from (values
      ('admin2@gentriwasa.test',    'Admin123!',    'Rosa Mendoza',    '09171230001', 'wasa_admin'),
      ('driver3@gentriwasa.test',   'Driver123!',   'Carlo Bautista',  '09171230002', 'driver'),
      ('driver4@gentriwasa.test',   'Driver123!',   'Joy Villanueva',  '09171230003', 'driver'),
      ('customer2@gentriwasa.test', 'Customer123!', 'Ramon Garcia',    '09171230004', 'public_consumer'),
      ('suspended@gentriwasa.test', 'Customer123!', 'Susana Lim',      '09171230005', 'public_consumer'),
      ('owner3@gentriwasa.test',    'Owner123!',    'Elena Ramos',     '09171230006', 'station_owner'),
      ('superadmin1@gentriwasa.test', 'Admin123!',  'Teresa Aquino',   '09171230007', 'wasa_superadmin'),
      ('superadmin2@gentriwasa.test', 'Admin123!',  'Nestor Villaroman', '09171230008', 'wasa_superadmin'),
      ('staff1@gentriwasa.test',    'Staff123!',    'Mylene Castro',   '09171230009', 'station_staff')
    ) as t(email, password, full_name, phone, role)
  loop
    if exists (select 1 from auth.users where email = acct.email) then
      continue;
    end if;

    v_id := gen_random_uuid();

    -- The handle_new_auth_user trigger creates the matching profiles row.
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      acct.email, crypt(acct.password, gen_salt('bf')),
      now(), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', acct.full_name),
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', acct.email), 'email', now(), now(), now());

    update profiles set phone_number = acct.phone, privacy_consented_at = now(), privacy_notice_version = 'seed'
     where id = v_id;

    if acct.role = 'station_staff' then
      insert into memberships (profile_id, association_id, role, station_id)
      values (v_id, v_association_id, 'station_staff', v_station1);

    elsif acct.role in ('wasa_admin', 'wasa_superadmin', 'public_consumer') then
      insert into memberships (profile_id, association_id, role, status)
      values (v_id, v_association_id, acct.role::app_role,
              case when acct.email = 'suspended@gentriwasa.test' then 'suspended' else 'active' end);

    elsif acct.role = 'driver' then
      insert into workers (station_id, profile_id, full_name, phone_number, vehicle_plate, jug_capacity, clearance_status)
      values (case when acct.email = 'driver3@gentriwasa.test' then v_station1 else v_station2 end,
              v_id, acct.full_name, acct.phone,
              case when acct.email = 'driver3@gentriwasa.test' then 'DRV3003' else 'DRV4004' end,
              18, 'cleared');
      insert into worker_station_history (worker_id, station_id, joined_at, status)
      select w.id, w.station_id, now() - interval '30 days', 'active' from workers w where w.profile_id = v_id;
      insert into memberships (profile_id, association_id, role, station_id)
      select v_id, v_association_id, 'driver', w.station_id from workers w where w.profile_id = v_id;

      -- Adding a worker creates their required credentials, pending review.
      -- Approve them so this driver is genuinely cleared rather than
      -- sitting in the officers' queue. The guard trigger only lets an
      -- officer approve, and there is no signed-in officer here.
      alter table worker_credentials disable trigger trg_prevent_worker_self_credential_approval;
      update worker_credentials set status = 'approved', reviewed_at = now()
       where worker_id = (select id from workers where profile_id = v_id);
      alter table worker_credentials enable trigger trg_prevent_worker_self_credential_approval;
      update workers set clearance_status = 'cleared' where profile_id = v_id;

    elsif acct.role = 'station_owner' then
      select id into v_barangay from barangays where association_id = v_association_id and name ilike 'Tejero%' limit 1;
      v_station3 := gen_random_uuid();
      -- Not accredited: sync_required_permits creates its permits, all
      -- waiting for upload.
      insert into water_stations (
        id, association_id, owner_profile_id, barangay_id, invite_code,
        station_name, station_address, latitude, longitude,
        price_per_jug, delivery_fee, offered_water_types
      ) values (
        v_station3, v_association_id, v_id, v_barangay, 'TEJERO1',
        'Tejero Aqua Station', 'Tejero, General Trias, Cavite',
        14.3870, 120.8710, 25.00, 20.00, array['purified']
      );
      insert into memberships (profile_id, association_id, role, station_id)
      values (v_id, v_association_id, 'station_owner', v_station3);
    end if;
  end loop;
end $$;

-- =====================================================================
-- VERIFY -- one line per account.
-- =====================================================================
select u.email, m.role, m.status,
       coalesce(ws.station_name, '') as station,
       coalesce(w.clearance_status::text, '') as driver_clearance,
       coalesce(ws.is_accredited::text, '') as station_accredited
  from auth.users u
  left join memberships m on m.profile_id = u.id
  left join water_stations ws on ws.id = m.station_id
  left join workers w on w.profile_id = u.id
 where u.email like '%@gentriwasa.test'
 order by m.role, u.email;
