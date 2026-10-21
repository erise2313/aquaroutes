-- =====================================================================
-- Finishing touches the test documents rely on (demo/testing only).
--
-- 1. Fixed staff codes STAFFBV / STAFFNV / STAFFTJ for Buenavista, Navarro
--    Springs and Tejero (new stations get a random one), so the documents
--    can name them.
-- 2. One flagged driver:
--
-- driver2@gentriwasa.test (Ana Cruz, Navarro Springs) gets a confirmed
-- incident, the way an officer would flag them: the confirm sets her
-- clearance to flagged association-wide (apply_incident_resolution). The
-- test cases need one -- a flagged driver can't be assigned, shows up in
-- the hire check, and can appeal.
--
-- driver1 is left cleared: seed_evaluation_data.sql gives driver1 the
-- delivery that is in progress.
--
-- Idempotent: does nothing if the incident is already there. Run after
-- seed_evaluation_data.sql. DO NOT run this against a production project.
-- =====================================================================

do $$
declare
  v_marker constant text := 'seed-flag';
  v_worker uuid;
  v_owner2 uuid;
  v_admin  uuid;
begin
  update water_stations ws set staff_invite_code = c.code
    from (values ('owner1@gentriwasa.test', 'STAFFBV'),
                 ('owner2@gentriwasa.test', 'STAFFNV'),
                 ('owner3@gentriwasa.test', 'STAFFTJ')) as c(email, code)
    join auth.users u on u.email = c.email
   where ws.owner_profile_id = u.id and ws.staff_invite_code is distinct from c.code;

  select w.id into v_worker from workers w join auth.users u on u.id = w.profile_id
   where u.email = 'driver2@gentriwasa.test';
  select id into v_owner2 from auth.users where email = 'owner2@gentriwasa.test';
  select id into v_admin from auth.users where email = 'admin@gentriwasa.test';
  if v_worker is null or v_owner2 is null or v_admin is null then
    raise exception 'Run seed_test_accounts.sql first: driver2, owner2 and admin are needed.';
  end if;

  if not exists (select 1 from worker_incidents where description like '%[' || v_marker || ']%') then
    insert into worker_incidents (worker_id, reported_by_profile_id, incident_type, description, amount_involved)
    values (v_worker, v_owner2, 'Cash shortage',
            'Remitted 3 deliveries short by a total of PHP 210 and did not explain the difference. [' || v_marker || ']',
            210.00);
    update worker_incidents
       set status = 'confirmed_flag', resolved_by = v_admin, resolved_at = now() - interval '2 days'
     where description like '%[' || v_marker || ']%';
  end if;
end $$;

-- VERIFY -- codes and driver clearance.
select station_code, station_name, invite_code, staff_invite_code from water_stations order by station_code;
select u.email, w.clearance_status
  from workers w join auth.users u on u.id = w.profile_id
 order by u.email;
