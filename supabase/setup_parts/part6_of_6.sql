-- GENTRI WASA setup -- PART 6 of 6. Run the parts in order,
-- each once, in the Supabase SQL Editor. (From setup_new_environment.sql.)

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



-- =====================================================================
-- FINAL CHECK -- compare each value with the expected one
-- =====================================================================
select 'tables and views in public (expect 53)' as item, count(*)::text as value
  from information_schema.tables where table_schema = 'public'
union all select 'app functions (expect 133)', count(*)::text
  from pg_proc p join pg_namespace s on s.oid = p.pronamespace
 where s.nspname = 'public' and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
union all select 'row security policies (expect 132)', count(*)::text from pg_policies where schemaname in ('public', 'storage')
union all select 'storage buckets (expect 7)', count(*)::text from storage.buckets
union all select 'private buckets (expect 3)', count(*)::text from storage.buckets where not public
union all select 'scheduled jobs (expect 2)', count(*)::text from cron.job
union all select 'realtime tables (expect 3)', count(*)::text from pg_publication_tables
 where pubname = 'supabase_realtime' and tablename in ('notifications', 'orders', 'workers')
union all select 'barangays (expect 33)', count(*)::text from barangays
union all select 'test login accounts (>= 20)', count(*)::text from auth.users where email like '%@gentriwasa.test'
union all select 'officer accounts (expect 6)', count(*)::text from memberships where role = 'wasa_admin'
union all select 'super admins (expect 2)', count(*)::text from memberships where role = 'wasa_superadmin'
union all select 'flagged drivers (expect 1)', count(*)::text from workers where clearance_status = 'flagged'
union all select 'stations (expect 3)', count(*)::text from water_stations
union all select 'publicly listed stations (>= 2)', count(*)::text from public_stations
union all select 'station products (expect 14)', count(*)::text from station_products
union all select 'orders (> 0)', count(*)::text from orders
union all select 'bulletins (> 0)', count(*)::text from bulletins
order by item;
