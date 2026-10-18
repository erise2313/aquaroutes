-- =====================================================================
-- Two new roles. RUN THIS FIRST, on its own, then
-- patch_roles_governance.sql.
--
--   wasa_superadmin  The association president and secretary (keep two).
--                    Creates, suspends and demotes officers, transfers a
--                    station to a new owner, sets association settings.
--                    Everything an officer can do, a super admin can too.
--   station_staff    A station's counter or dispatch person. Takes orders,
--                    assigns drivers, updates order status -- nothing else
--                    (no permits, prices, products, drivers or settlements).
--
-- Postgres won't let a new enum value be used in the transaction that
-- added it, which is why this is a separate file. Idempotent.
-- =====================================================================

alter type app_role add value if not exists 'wasa_superadmin';
alter type app_role add value if not exists 'station_staff';

-- VERIFY -- both listed.
select enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'app_role' order by e.enumsortorder;
