-- =====================================================================
-- Lets a WASA admin manually certify a station as accredited even if it
-- has missing/rejected required permits -- a deliberate judgment-call
-- override, not a bypass of the normal automatic process. Tracks who
-- did it and when for accountability, and makes the override actually
-- stick: previously, even if an admin force-set is_accredited = true
-- directly, the very next permit status change would silently revert it
-- via recompute_accreditation(), since that trigger always recomputed
-- from scratch with no concept of a manual override.
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

alter table water_stations add column if not exists accreditation_override_by uuid references profiles(id);
alter table water_stations add column if not exists accreditation_override_at timestamptz;

create or replace function recompute_accreditation() returns trigger as $$
declare
  all_ok boolean;
  v_override_active boolean;
begin
  select (accreditation_override_by is not null) into v_override_active
    from water_stations where id = new.station_id;

  if v_override_active then
    -- A WASA admin has manually certified this station regardless of
    -- permit status -- don't let a later permit change silently undo it.
    return new;
  end if;

  select not exists (
    select 1 from permits
    where station_id = new.station_id
      and is_required = true
      and status <> 'approved'
  ) into all_ok;

  update water_stations
    set is_accredited = all_ok,
        accreditation_status = case
          when all_ok then 'accredited'
          when accreditation_status = 'accredited' then 'under_review'
          else accreditation_status
        end,
        updated_at = now()
    where id = new.station_id;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- wasa_admin only (also enforced here, not just relying on RLS, since
-- this deliberately writes is_accredited/accreditation_status --
-- prevent_owner_self_accreditation() already blocks non-admins from
-- touching those columns directly, but this RPC is the sanctioned path).
create or replace function set_accreditation_override(p_station_id uuid, p_enable boolean) returns void as $$
declare
  v_all_ok boolean;
begin
  if not auth_has_role('wasa_admin') then
    raise exception 'Only WASA admin may override a station''s accreditation.';
  end if;

  if p_enable then
    update water_stations
      set is_accredited = true,
          accreditation_status = 'accredited',
          accreditation_override_by = auth.uid(),
          accreditation_override_at = now(),
          updated_at = now()
      where id = p_station_id;
  else
    -- Clear the override and immediately recompute from the station's
    -- actual current permit statuses, instead of leaving it stuck
    -- accredited until the next unrelated permit change happens to fire
    -- the trigger.
    select not exists (
      select 1 from permits
      where station_id = p_station_id and is_required = true and status <> 'approved'
    ) into v_all_ok;

    update water_stations
      set accreditation_override_by = null,
          accreditation_override_at = null,
          is_accredited = v_all_ok,
          accreditation_status = case when v_all_ok then 'accredited' else 'under_review' end,
          updated_at = now()
      where id = p_station_id;
  end if;
end;
$$ language plpgsql security definer set search_path = public;
