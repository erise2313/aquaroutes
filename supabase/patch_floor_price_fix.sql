-- =====================================================================
-- Incremental patch: fix floor price duplication bug.
--
-- BulletinService.setFloorPrice() was a plain INSERT with no unique
-- constraint backing it, so re-setting a price for a water type that
-- already had one created a second row instead of updating it -- and
-- there was no delete action anywhere, so a bad entry was stuck forever.
--
-- This patch:
--   1. Deduplicates any existing floor_prices rows per (association_id,
--      water_type), keeping only the most recently created one per pair
--      (safe to run even if you have no duplicates -- it's a no-op then).
--   2. Adds a unique constraint on (association_id, water_type) so this
--      can't happen again.
--   3. Adds the missing floor_prices_admin_delete RLS policy so the new
--      in-app "Remove" action works.
--
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Deduplicate existing rows, keep the newest per (association_id, water_type)
-- ---------------------------------------------------------------------
delete from floor_prices fp
where fp.id not in (
  select distinct on (association_id, water_type) id
  from floor_prices
  order by association_id, water_type, created_at desc
);

-- ---------------------------------------------------------------------
-- 2. Unique constraint
-- ---------------------------------------------------------------------
alter table floor_prices
  add constraint floor_prices_association_id_water_type_key unique (association_id, water_type);

-- ---------------------------------------------------------------------
-- 3. Missing delete policy
-- ---------------------------------------------------------------------
drop policy if exists floor_prices_admin_delete on floor_prices;
create policy floor_prices_admin_delete on floor_prices for delete
  using (auth_has_role('wasa_admin'));
