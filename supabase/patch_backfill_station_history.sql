-- =====================================================================
-- Backfill: workers assigned to a station but with no station history.
--
-- worker_station_history rows are written by exactly two functions --
-- register_driver_for_station() and driver_switch_station(). Anything
-- that puts a row into `workers` by another route leaves no history, and
-- seed_test_accounts.sql does exactly that, so the seeded demo drivers
-- show "No station history" in Hire Check.
--
-- This is a gap in the demo data, not in the application: no client code
-- inserts into `workers` at all, so a driver who registers through the
-- app always gets a history row. The effect is only that a working
-- feature looks broken when demonstrated.
--
-- Raised by the evaluator on 10 October 2026 (GTW-WEB-14), who noticed
-- Ana Cruz had no history despite being assigned to a station.
--
-- Safe to re-run: it adds a row only where an active one is missing, so
-- it cannot violate worker_station_history_one_active (the unique index
-- permitting one 'active' row per worker) and cannot duplicate anything.
-- =====================================================================

insert into worker_station_history (worker_id, station_id, joined_at, status)
select w.id, w.station_id, coalesce(w.created_at, now()), 'active'
  from workers w
 where w.station_id is not null
   and not exists (
     select 1 from worker_station_history h
      where h.worker_id = w.id and h.status = 'active'
   );

-- =====================================================================
-- VERIFY -- every assigned worker should now have an active history row.
-- =====================================================================
select
  w.full_name,
  ws.station_name,
  case when h.worker_id is null then 'STILL MISSING' else 'has history' end as station_history
from workers w
left join water_stations ws on ws.id = w.station_id
left join worker_station_history h
       on h.worker_id = w.id and h.status = 'active'
where w.station_id is not null
order by w.full_name;
