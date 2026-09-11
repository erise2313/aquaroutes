-- =====================================================================
-- Fix: a station owner with approved alkaline permits could not save their
-- station profile at all -- not even a name change.
--
-- Two triggers combined:
--   * trg_sync_required_permits fires AFTER UPDATE OF offered_water_types,
--     i.e. whenever that column is in the SET list -- and the profile screen
--     always sends it. It then re-upserted the alkaline permits with
--     DO UPDATE SET is_required = true even when they already were.
--   * That no-op UPDATE of an approved permit tripped
--     prevent_owner_self_permit_approval, which raised whenever a non-admin
--     updated a permit whose new.status = 'approved' -- whether or not
--     anything was being approved.
--
-- Found when the product-catalog migration (which updates stations' water
-- types) failed on Buenavista, whose alkaline permits are approved.
--
-- 1. An approval is a status CHANGE to approved, not "the row is approved".
-- 2. The permit sync does nothing when the water types didn't change, and
--    never rewrites a permit whose is_required already has the target value.
--
-- Idempotent -- safe to run more than once.
-- =====================================================================

create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if (new.status = 'approved' and new.status is distinct from old.status)
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function sync_required_permits() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    if new.offered_water_types is not distinct from old.offered_water_types then
      return new;
    end if;
  end if;

  insert into permits (station_id, permit_type, is_required)
    values
      (new.id, 'business_permit', true),
      (new.id, 'sanitary_permit', true),
      (new.id, 'fda_license', true),
      (new.id, 'fire_safety_certificate', true),
      (new.id, 'nwrb_water_permit', true),
      (new.id, 'nwrb_certificate_of_public_convenience', true),
      (new.id, 'water_quality_test_report', true),
      (new.id, 'operator_training_certificate', true)
    on conflict (station_id, permit_type) do nothing;

  if 'alkaline' = any(new.offered_water_types) then
    insert into permits (station_id, permit_type, is_required)
      values
        (new.id, 'alkaline_tech_cert', true),
        (new.id, 'alkaline_water_test', true)
      on conflict (station_id, permit_type) do update set is_required = true
        where permits.is_required is distinct from true;
  else
    update permits set is_required = false
      where station_id = new.id
        and permit_type in ('alkaline_tech_cert', 'alkaline_water_test')
        and is_required;
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;
