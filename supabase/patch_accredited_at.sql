-- Records WHEN a station became accredited, so the admin dashboard can chart
-- accreditations over time.
--
-- Why this is needed: water_stations has created_at (registered),
-- updated_at (last edited, for any reason) and accreditation_override_at
-- (manual certification only). None of them answers "when did this station
-- become accredited". Charting updated_at would silently mislabel "someone
-- edited the phone number" as "accredited this month".
--
-- Why a trigger rather than editing the functions that grant accreditation:
-- is_accredited is written from two places -- recompute_accreditation()
-- (patch_admin_accreditation_override.sql) when a permit changes, and
-- set_accreditation_override() when an admin manually certifies. A BEFORE
-- UPDATE trigger on the transition catches both, plus any future path,
-- without touching either function's logic.
--
-- Historical rows stay null on purpose: there is no honest way to backfill a
-- date that was never recorded, so the dashboard labels its earliest bucket
-- rather than inventing history. Idempotent -- safe to run more than once.

alter table water_stations add column if not exists accredited_at timestamptz;

comment on column water_stations.accredited_at is
  'When is_accredited last became true. Null for stations accredited before this column existed, and cleared if accreditation is lost.';

create or replace function stamp_accredited_at() returns trigger as $$
begin
  if new.is_accredited and not coalesce(old.is_accredited, false) then
    -- false -> true: this is the moment of accreditation.
    new.accredited_at := now();
  elsif not new.is_accredited then
    -- Lost (or never had) accreditation. Clearing means a station that is
    -- re-accredited later gets the new date rather than a stale first one,
    -- which is what "accredited this quarter" should count.
    new.accredited_at := null;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at on water_stations;
create trigger trg_stamp_accredited_at
  before update on water_stations
  for each row
  when (old.is_accredited is distinct from new.is_accredited)
  execute function stamp_accredited_at();

-- A station inserted already accredited would otherwise never fire the
-- update trigger.
create or replace function stamp_accredited_at_insert() returns trigger as $$
begin
  if new.is_accredited then
    new.accredited_at := coalesce(new.accredited_at, now());
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_stamp_accredited_at_insert on water_stations;
create trigger trg_stamp_accredited_at_insert
  before insert on water_stations
  for each row
  execute function stamp_accredited_at_insert();

create index if not exists water_stations_accredited_at_idx
  on water_stations (accredited_at)
  where accredited_at is not null;
