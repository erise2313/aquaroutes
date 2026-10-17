-- =====================================================================
-- Demo data for the modules that look broken when they are empty.
--
-- For a project that already holds real data (unlike seed_evaluation_data.sql,
-- which expects the seeded test accounts by email). It picks existing
-- stations, an existing customer and an existing driver, and only adds what
-- is missing:
--
--   * jug balances between two stations, and one proposed settlement
--     (the clearinghouse is otherwise blank)
--   * three pending orders (the owner's queue, driver assignment)
--   * one flagged driver, via a confirmed incident (registry, hire check,
--     the "flagged driver" test cases)
--   * one approved permit expiring in three weeks (renewal warnings)
--
-- Safe to re-run: orders it created are replaced, and the other rows are
-- added only when none exist yet. Every row it writes is marked
-- "demo-gaps" so it can be found and removed later (see the end).
--
-- Resources cannot be seeded here: they are files in Storage. Upload two
-- from Desktop\GenTriWASA-Test-Uploads\3 Resources (officer) through the
-- admin portal instead.
-- =====================================================================

do $$
declare
  v_marker    constant text := 'demo-gaps';
  v_station1  uuid;
  v_station2  uuid;
  v_owner1    uuid;
  v_customer  uuid;
  v_admin     uuid;
  v_worker    uuid;
  v_loc       geography(point, 4326) := st_setsrid(st_makepoint(120.8805, 14.3762), 4326)::geography;
begin
  -- Two stations, accredited first so the orders are ones customers could
  -- really have placed.
  select id, owner_profile_id into v_station1, v_owner1
    from water_stations order by is_accredited desc, created_at limit 1;
  select id into v_station2
    from water_stations where id <> v_station1 order by is_accredited desc, created_at limit 1;
  select profile_id into v_customer from memberships
    where role = 'public_consumer' and status = 'active' order by created_at limit 1;
  select profile_id into v_admin from memberships
    where role = 'wasa_admin' and status = 'active' order by created_at limit 1;
  select id into v_worker from workers order by created_at limit 1;

  if v_station1 is null or v_station2 is null then
    raise exception 'Need at least two stations.';
  end if;

  -- Pending orders (replaced on every run).
  delete from orders where client_request_id like v_marker || '%';
  insert into orders (
    station_id, customer_profile_id, delivery_location,
    jugs_ordered, water_type, jug_type, status, payment_method,
    subtotal, delivery_fee, total_amount, customer_phone,
    client_request_id, created_at
  ) values
    (v_station1, v_customer, v_loc, 2, 'purified', 'slim_5gal', 'pending', 'cash',
     50.00, 20.00, 70.00, '09170000101', v_marker || '-1', now() - interval '8 minutes'),
    (v_station1, v_customer, v_loc, 3, 'alkaline', 'round_5gal', 'pending', 'cash',
     90.00, 20.00, 110.00, '09170000102', v_marker || '-2', now() - interval '22 minutes'),
    (v_station2, v_customer, v_loc, 1, 'mineral', 'round_5gal', 'pending', 'cash',
     25.00, 15.00, 40.00, '09170000103', v_marker || '-3', now() - interval '40 minutes');

  -- Jug balances, only if the clearinghouse is empty.
  if not exists (select 1 from jug_ledger_entries) then
    insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by, created_at)
    values
      (v_station1, v_station2, 'slim_5gal', 14, v_owner1, now() - interval '12 days'),
      (v_station1, v_station2, 'round_5gal', 6, v_owner1, now() - interval '6 days'),
      (v_station2, v_station1, 'slim_5gal', 9, v_owner1, now() - interval '9 days');
  end if;

  if not exists (select 1 from jug_settlements where status = 'proposed') then
    insert into jug_settlements (holder_station_id, owner_station_id, jug_type, quantity, status, proposed_by, created_at)
    values (v_station2, v_station1, 'slim_5gal', 5, 'proposed', v_owner1, now() - interval '1 day');
  end if;

  -- A flagged driver: file an incident and confirm it. The confirm sets the
  -- worker's clearance to flagged through apply_incident_resolution.
  if v_worker is not null and v_owner1 is not null
     and not exists (select 1 from worker_incidents where description like '%[' || v_marker || ']%') then
    insert into worker_incidents (worker_id, reported_by_profile_id, incident_type, description, amount_involved)
    values (v_worker, v_owner1, 'Cash shortage',
            'Remitted 3 deliveries short by a total of PHP 210. Driver did not explain the difference. [' || v_marker || ']',
            210.00);
    update worker_incidents
       set status = 'confirmed_flag', resolved_by = v_admin, resolved_at = now()
     where description like '%[' || v_marker || ']%';
  end if;

  -- An approved permit expiring in three weeks, for the renewal warnings.
  alter table permits disable trigger trg_prevent_owner_self_permit_approval;
  update permits
     set expiry_date = (current_date + interval '21 days')::date
   where id = (
     select id from permits
      where station_id = v_station1 and status = 'approved'
      order by permit_type limit 1
   )
   and (expiry_date is null or expiry_date > current_date + interval '30 days');
  alter table permits enable trigger trg_prevent_owner_self_permit_approval;

  raise notice 'Demo gaps filled for stations % and %.', v_station1, v_station2;
end $$;

-- =====================================================================
-- VERIFY
-- =====================================================================
select 'pending orders' as item, count(*)::text as n from orders where status = 'pending'
union all select 'jug ledger entries', count(*)::text from jug_ledger_entries
union all select 'settlements awaiting confirmation', count(*)::text from jug_settlements where status = 'proposed'
union all select 'flagged workers', count(*)::text from workers where clearance_status = 'flagged'
union all select 'approved permits expiring within 30 days', count(*)::text
  from permits where status = 'approved' and expiry_date <= current_date + interval '30 days'
order by item;

-- To remove what this script added (orders and the incident; the ledger and
-- settlement rows are ordinary data once in use):
--   delete from orders where client_request_id like 'demo-gaps%';
--   update worker_incidents set status = 'dismissed' where description like '%[demo-gaps]%';
