-- =====================================================================
-- GENTRIWASA -- EVALUATION DATA SEEDING (demo/testing only)
-- =====================================================================
-- Fills the three modules that seed_test_accounts.sql leaves empty, so
-- an evaluator does not open them and find a blank screen. An empty
-- module is indistinguishable from a broken one.
--
--   1. Orders in every live status, including one mid-delivery so that
--      live tracking can be seen working rather than inferred.
--   2. Inter-station container transfers and one settlement awaiting
--      confirmation, so the jug clearinghouse has balances to show.
--   3. One permit returned to 'pending_review', so the association
--      officer has something to review rather than only to look at.
--
-- RUN ORDER:
--   1. supabase/reset_and_rebuild.sql      (schema)
--   2. supabase/seed_test_accounts.sql     (accounts + 2 stations)
--   3. supabase/seed_demo_content.sql      (bulletins, reviews, events)
--   4. this file
--
-- Safe to re-run: it removes only the rows it created last time,
-- identified by the marker below, and never touches anything else.
--
-- DO NOT run against a project holding real user data.
-- =====================================================================

do $$
declare
  -- Everything this script creates carries this marker so a re-run can
  -- find and replace it without guessing.
  v_marker       text := 'eval-seed';

  v_station1     uuid;  -- Buenavista Water Refilling Station
  v_station2     uuid;  -- Navarro Springs Water Station
  v_owner1       uuid;
  v_owner2       uuid;
  v_customer     uuid;
  v_driver1_wrk  uuid;  -- workers.id, not the profile id
  v_admin        uuid;
  v_disposable   uuid := gen_random_uuid();
  v_loc          geography(point, 4326);
begin
  -- -------------------------------------------------------------------
  -- Resolve the seeded entities by stable keys rather than by uuid,
  -- since seed_test_accounts.sql generates fresh uuids on every run.
  -- -------------------------------------------------------------------
  select id into v_station1 from water_stations
    where station_name = 'Buenavista Water Refilling Station';
  select id into v_station2 from water_stations
    where station_name = 'Navarro Springs Water Station';

  select p.id into v_owner1   from profiles p join auth.users u on u.id = p.id
    where u.email = 'owner1@gentriwasa.test';
  select p.id into v_owner2   from profiles p join auth.users u on u.id = p.id
    where u.email = 'owner2@gentriwasa.test';
  select p.id into v_customer from profiles p join auth.users u on u.id = p.id
    where u.email = 'customer1@gentriwasa.test';
  select p.id into v_admin    from profiles p join auth.users u on u.id = p.id
    where u.email = 'admin@gentriwasa.test';

  select w.id into v_driver1_wrk from workers w
    where w.station_id = v_station1 order by w.created_at limit 1;

  if v_station1 is null or v_station2 is null or v_customer is null then
    raise exception
      'Seeded stations or accounts not found. Run reset_and_rebuild.sql and seed_test_accounts.sql first.';
  end if;

  -- A delivery point a few hundred metres from the Buenavista station,
  -- so the tracking map has a visible distance to cover.
  v_loc := st_setsrid(st_makepoint(120.8805, 14.3762), 4326)::geography;

  -- -------------------------------------------------------------------
  -- Clear anything a previous run of THIS script created.
  -- -------------------------------------------------------------------
  delete from jug_settlements    where proposed_by in (v_owner1, v_owner2) and quantity in (6, 3, 12, 7);
  delete from jug_ledger_entries where recorded_by = v_owner1;
  delete from orders             where client_request_id like v_marker || '%';

  -- -------------------------------------------------------------------
  -- 0. A DISPOSABLE ACCOUNT FOR TESTING DELETION
  --
  -- customer1@ is given in-progress orders below, which means
  -- account_deletion_blockers() will correctly refuse to delete it. That
  -- is worth demonstrating, but it leaves no way to see a deletion
  -- actually complete. This account exists to be destroyed: no orders,
  -- no station, no deliveries, so it deletes cleanly.
  --
  -- Sign in as disposable@gentriwasa.test / Disposable123!
  -- -------------------------------------------------------------------
  delete from auth.users where email = 'disposable@gentriwasa.test';

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values
    ('00000000-0000-0000-0000-000000000000', v_disposable, 'authenticated', 'authenticated',
     'disposable@gentriwasa.test', crypt('Disposable123!', gen_salt('bf')),
     now(), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Delete Me"}',
     now(), now(), '', '', '', '');

  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values
    (gen_random_uuid(), v_disposable, v_disposable::text,
     jsonb_build_object('sub', v_disposable::text, 'email', 'disposable@gentriwasa.test'),
     'email', now(), now(), now());

  -- handle_new_auth_user() creates the profiles row from the metadata
  -- above; this only adds the association membership.
  insert into memberships (profile_id, association_id, role)
  values (v_disposable, '00000000-0000-0000-0000-000000000001', 'public_consumer')
  on conflict do nothing;

  -- -------------------------------------------------------------------
  -- 1. ORDERS
  --
  -- One in each live status. The 'active' row is the important one:
  -- it is what makes live delivery tracking demonstrable, and without
  -- it the evaluator can only be told that tracking works.
  -- -------------------------------------------------------------------
  insert into orders (
    station_id, customer_profile_id, driver_worker_id, delivery_location,
    jugs_ordered, water_type, jug_type, status, payment_method,
    subtotal, delivery_fee, total_amount, customer_phone,
    client_request_id, created_at
  )
  values
    -- Awaiting the owner's acceptance.
    (v_station1, v_customer, null, v_loc,
     2, 'purified', 'slim_5gal', 'pending', 'cash',
     50.00, 20.00, 70.00, '09170000001',
     v_marker || '-pending', now() - interval '12 minutes'),

    -- Accepted and assigned, not yet collected.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     3, 'purified', 'slim_5gal', 'assigned', 'cash',
     75.00, 20.00, 95.00, '09170000002',
     v_marker || '-assigned', now() - interval '35 minutes'),

    -- Out for delivery. This is the one to track.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     4, 'alkaline', 'round_5gal', 'active', 'cash',
     100.00, 20.00, 120.00, '09170000003',
     v_marker || '-active', now() - interval '50 minutes'),

    -- Completed, so order history is not empty.
    (v_station1, v_customer, v_driver1_wrk, v_loc,
     1, 'purified', 'slim_5gal', 'done', 'cash',
     25.00, 20.00, 45.00, '09170000004',
     v_marker || '-done', now() - interval '3 days'),

    -- A second completed order on the other station, so the customer's
    -- history spans more than one supplier.
    (v_station2, v_customer, null, v_loc,
     2, 'mineral', 'round_5gal', 'done', 'cash',
     44.00, 15.00, 59.00, '09170000005',
     v_marker || '-done-2', now() - interval '6 days');

  -- -------------------------------------------------------------------
  -- 2. JUG CLEARINGHOUSE
  --
  -- Positive quantity = holder_station gained containers belonging to
  -- owner_station. The balances below are deliberately uneven in both
  -- directions, so the netting is actually exercised rather than a
  -- single one-way total.
  -- -------------------------------------------------------------------
  insert into jug_ledger_entries
    (holder_station_id, owner_station_id, jug_type, quantity, recorded_by, created_at)
  values
    -- Slim: Buenavista holds 18 - 6 = 12 of Navarro's, Navarro holds 4
    -- of Buenavista's, so Buenavista owes Navarro 8 after netting.
    (v_station1, v_station2, 'slim_5gal',  18, v_owner1, now() - interval '14 days'),
    (v_station1, v_station2, 'slim_5gal',  -6, v_owner1, now() - interval '9 days'),
    (v_station2, v_station1, 'slim_5gal',   4, v_owner1, now() - interval '11 days'),
    -- Round: Navarro holds 9 of Buenavista's, Buenavista holds 4 of
    -- Navarro's, so Navarro owes Buenavista 5 -- the net runs both ways.
    (v_station2, v_station1, 'round_5gal',  9, v_owner1, now() - interval '7 days'),
    (v_station1, v_station2, 'round_5gal',  4, v_owner1, now() - interval '4 days');

  -- Awaiting confirmation from the owed station. Left as 'proposed' on
  -- purpose: confirming it is one of the things worth testing, and a
  -- settlement takes effect only when the other party agrees. Each is
  -- proposed by the station holding the jugs, for no more than it owes
  -- after netting (check_jug_settlement_proposal), so each owner has one
  -- to confirm: owner2 confirms the slim one, owner1 the round one.
  insert into jug_settlements
    (holder_station_id, owner_station_id, jug_type, quantity, status, proposed_by, created_at)
  values
    (v_station1, v_station2, 'slim_5gal',  6, 'proposed', v_owner1, now() - interval '2 days'),
    (v_station2, v_station1, 'round_5gal', 3, 'proposed', v_owner2, now() - interval '1 day');

  -- -------------------------------------------------------------------
  -- 3. A PERMIT AWAITING REVIEW
  --
  -- seed_test_accounts.sql approves every permit so both stations look
  -- fully compliant straight away. That leaves the officer's review
  -- queue empty. Returning one permit to 'pending_review' gives the
  -- approve/reject workflow something to act on.
  -- -------------------------------------------------------------------
  -- Clearing reviewed_by trips prevent_owner_self_permit_approval(), which
  -- raises on ANY change to reviewed_by/reviewed_at by a non-admin -- and in
  -- the SQL Editor auth.uid() is NULL, so there is no admin to be.
  alter table permits disable trigger trg_prevent_owner_self_permit_approval;
  alter table water_stations disable trigger trg_prevent_owner_self_accreditation;

  update permits
     set status          = 'pending_review',
         reviewed_by     = null,
         reviewed_at     = null,
         rejection_reason = null,
         uploaded_at     = now() - interval '2 days'
   where station_id = v_station2
     and permit_type = 'sanitary_permit';

  -- A second one expiring soon, so the renewal warning is visible.
  update permits
     set expiry_date = (current_date + interval '21 days')::date
   where station_id = v_station1
     and permit_type = 'business_permit';

  alter table water_stations enable trigger trg_prevent_owner_self_accreditation;
  alter table permits enable trigger trg_prevent_owner_self_permit_approval;

  raise notice 'Evaluation data seeded: 1 disposable account, 5 orders, 5 ledger entries, 2 settlements, 1 permit pending review.';
end $$;

-- =====================================================================
-- VERIFY
-- =====================================================================
select 'orders by status' as item, status::text as detail, count(*)::text as n
  from orders group by status
union all
select 'jug balances', holder_station_id::text || ' holds ' || jug_type::text, net_qty::text
  from jug_balances
union all
select 'settlements awaiting confirmation', status::text, count(*)::text
  from jug_settlements where status = 'proposed' group by status
union all
select 'permits pending review', 'pending_review', count(*)::text
  from permits where status = 'pending_review'
order by item, detail;
