-- =====================================================================
-- Hardening from Supabase's security advisor, 17 October 2026.
--
-- Idempotent -- safe to run more than once. Run after every earlier patch.
--
-- 1. Jug balances were readable by anyone holding the publishable key.
--
--    jug_balances is a view over jug_ledger_entries. Views run with their
--    creator's rights by default, which skips the ledger's RLS -- so
--    `select * from jug_balances` with the key that ships in every APK and
--    web build returned every station's balances with every other station,
--    signed in or not. The ledger's own policies already say who should see
--    what (an owner: rows their station is part of; officers: everything),
--    so the view now runs with the caller's rights and those policies apply.
--    The clearinghouse screen already filters to the owner's station, so it
--    sees exactly what it did before. Drivers never read this view.
--
--    bulletin_reaction_counts gets the same switch. Reactions are publicly
--    readable anyway, so nothing changes for anyone; it just stops being an
--    exception to RLS.
--
--    public_stations deliberately stays as it is: it is the public
--    directory -- a fixed set of columns from accredited, active stations --
--    and water_stations' RLS rightly hides those rows from visitors.
--
-- 2. Seven functions did not pin search_path.
--
--    Without it a function resolves table and function names through the
--    caller's search_path, which a caller can change. Pinned to public,
--    matching every security definer function in this project.
--
-- 3. sync_station_from_products() could be called by anyone.
--
--    It recomputes a station's prices and water types from its products,
--    and is meant to run only from the two triggers that call it (both
--    security definer, so they keep the right to). Called directly it
--    did no harm beyond needless work, but it has no reason to be public.
-- =====================================================================

-- 1.
alter view jug_balances set (security_invoker = true);
alter view bulletin_reaction_counts set (security_invoker = true);

-- 2.
alter function get_pending_orders(uuid) set search_path = public;
alter function get_active_orders(uuid) set search_path = public;
alter function generate_worker_code() set search_path = public;
alter function peso_text(numeric) set search_path = public;
alter function stamp_accredited_at() set search_path = public;
alter function stamp_accredited_at_insert() set search_path = public;
alter function station_products_touch_updated_at() set search_path = public;

-- 3.
revoke execute on function sync_station_from_products(uuid) from public, anon, authenticated;

-- =====================================================================
-- VERIFY -- every line should say "ok".
-- =====================================================================
select item, case when ok then 'ok' else 'NOT APPLIED' end as result from (
  select 'jug_balances respects RLS' as item,
         coalesce((select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.jug_balances'::regclass), false) as ok
  union all
  select 'bulletin_reaction_counts respects RLS',
         coalesce((select 'security_invoker=true' = any(reloptions) from pg_class where oid = 'public.bulletin_reaction_counts'::regclass), false)
  union all
  select 'search_path pinned on all seven',
         not exists (
           select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('get_pending_orders', 'get_active_orders', 'generate_worker_code', 'peso_text',
                                'stamp_accredited_at', 'stamp_accredited_at_insert', 'station_products_touch_updated_at')
              and not coalesce(p.proconfig::text like '%search_path=public%', false))
  union all
  select 'sync_station_from_products not callable by visitors',
         not has_function_privilege('anon', 'public.sync_station_from_products(uuid)', 'execute')
     and not has_function_privilege('authenticated', 'public.sync_station_from_products(uuid)', 'execute')
) t;
