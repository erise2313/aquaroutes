-- =====================================================================
-- Incremental patch: Security & Reliability Audit Remediation (Tier 0 + 1)
-- Additive/corrective to your existing schema -- no data loss. Run this
-- once against your already-provisioned database (paste into the Supabase
-- SQL Editor). Safe to re-run: every `create or replace function` and
-- `drop ... if exists` is idempotent.
--
-- Fixes, in order:
--   T0.1-2  Station owner self-registration was broken end-to-end (no RLS
--           policy let the client INSERT a memberships row), and
--           stations_owner_all let ANY signed-in user insert+own an
--           arbitrary water_stations row with no role check at all.
--   T0.3    Nothing stopped an owner/worker directly UPDATE-ing their own
--           accreditation/permit-approval/credential-approval columns,
--           self-granting trust status that's supposed to require WASA
--           admin review.
--   T0.4    Three RPCs used `x <> auth_station_id()` as their auth guard,
--           which evaluates to NULL (not true) when the caller has no
--           station membership -- silently skipping the exception and
--           letting any signed-in user call them.
--   T0.5    Dismissing one confirmed incident against a worker cleared
--           them even if other confirmed incidents still existed;
--           credential-driven clearance ignored an unresolved incident.
--   T1.1    Admin permit/credential review screens never surfaced a way
--           to actually view the uploaded document before approving it.
--   T1.4    orders_driver_update let a driver rewrite financial/station
--           fields on an order, not just operational ones.
--   T1.5    accreditation_status could go stale relative to is_accredited
--           after a permit was rejected post-approval.
--   T1.6    Nothing enforced posted_by/author_role on bulletin inserts,
--           so a driver could impersonate an official WASA announcement.
-- =====================================================================


-- ---------------------------------------------------------------------
-- T0.1-2: register_station_owner RPC + split stations_owner_all policy
-- ---------------------------------------------------------------------
create or replace function register_station_owner(
  p_station_name text,
  p_station_address text,
  p_invite_code text,
  p_latitude double precision,
  p_longitude double precision
) returns uuid as $$
declare
  v_association_id uuid;
  v_station_id uuid;
begin
  select id into v_association_id from associations limit 1;
  if v_association_id is null then
    raise exception 'No association configured.';
  end if;

  insert into water_stations (association_id, owner_profile_id, invite_code, station_name, station_address, latitude, longitude)
    values (v_association_id, auth.uid(), p_invite_code, p_station_name, p_station_address, p_latitude, p_longitude)
    returning id into v_station_id;

  insert into memberships (profile_id, association_id, role, station_id)
    values (auth.uid(), v_association_id, 'station_owner', v_station_id);

  return v_station_id;
end;
$$ language plpgsql security definer set search_path = public;

drop policy if exists stations_owner_all on water_stations;

create policy stations_owner_select on water_stations for select
  using (owner_profile_id = auth.uid());
create policy stations_owner_update on water_stations for update
  using (owner_profile_id = auth.uid())
  with check (owner_profile_id = auth.uid());
create policy stations_owner_delete on water_stations for delete
  using (owner_profile_id = auth.uid());

-- ---------------------------------------------------------------------
-- T0.3: guard triggers preventing self-approval of trust-granting columns
-- ---------------------------------------------------------------------
create or replace function prevent_owner_self_accreditation() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.is_accredited is distinct from old.is_accredited
       or new.accreditation_status is distinct from old.accreditation_status
       or new.is_colorum_verified is distinct from old.is_colorum_verified then
      raise exception 'Only WASA admin may change accreditation or verification status.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_prevent_owner_self_accreditation on water_stations;
create trigger trg_prevent_owner_self_accreditation
  before update on water_stations
  for each row execute function prevent_owner_self_accreditation();

create or replace function prevent_owner_self_permit_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.status = 'approved'
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a permit.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_prevent_owner_self_permit_approval on permits;
create trigger trg_prevent_owner_self_permit_approval
  before update on permits
  for each row execute function prevent_owner_self_permit_approval();

create or replace function prevent_worker_self_credential_approval() returns trigger as $$
begin
  if not auth_has_role('wasa_admin') then
    if new.status = 'approved'
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at then
      raise exception 'Only WASA admin may approve a credential.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_prevent_worker_self_credential_approval on worker_credentials;
create trigger trg_prevent_worker_self_credential_approval
  before update on worker_credentials
  for each row execute function prevent_worker_self_credential_approval();

-- ---------------------------------------------------------------------
-- T0.4: NULL-safe auth checks in owner_remove_worker / confirm_jug_settlement / reject_jug_settlement
-- ---------------------------------------------------------------------
create or replace function owner_remove_worker(p_worker_id uuid) returns void as $$
declare
  v_station_id uuid;
  v_profile_id uuid;
begin
  select station_id, profile_id into v_station_id, v_profile_id from workers where id = p_worker_id;

  if v_station_id is null or auth_station_id() is null or v_station_id <> auth_station_id() then
    raise exception 'Not authorized to remove this worker.';
  end if;

  update workers set station_id = null, updated_at = now() where id = p_worker_id;
  if v_profile_id is not null then
    update memberships set station_id = null where profile_id = v_profile_id and role = 'driver';
  end if;
  update worker_station_history set status = 'removed', left_at = now(), ended_by_profile_id = auth.uid()
    where worker_id = p_worker_id and status = 'active';
end;
$$ language plpgsql security definer set search_path = public;

create or replace function confirm_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if auth_station_id() is null or auth_station_id() <> s.owner_station_id then
    raise exception 'only the owning/receiving station may confirm this settlement';
  end if;

  insert into jug_ledger_entries (holder_station_id, owner_station_id, jug_type, quantity, recorded_by)
    values (s.holder_station_id, s.owner_station_id, s.jug_type, -s.quantity, auth.uid());

  update jug_settlements
    set status = 'confirmed', confirmed_by = auth.uid(), confirmed_at = now()
    where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function reject_jug_settlement(p_settlement_id uuid) returns void as $$
declare
  s jug_settlements%rowtype;
begin
  select * into s from jug_settlements where id = p_settlement_id for update;

  if not found then
    raise exception 'settlement not found';
  end if;

  if s.status <> 'proposed' then
    raise exception 'settlement is not in proposed state';
  end if;

  if (auth_station_id() is null or auth_station_id() <> s.owner_station_id) and not auth_has_role('wasa_admin') then
    raise exception 'only the owning/receiving station or a WASA admin may reject this settlement';
  end if;

  update jug_settlements set status = 'rejected' where id = p_settlement_id;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- T0.5: incident-dismissal and credential-reclearance trigger logic
-- ---------------------------------------------------------------------
create or replace function apply_incident_resolution() returns trigger as $$
begin
  if new.status = 'confirmed_flag' and old.status <> 'confirmed_flag' then
    update workers set clearance_status = 'flagged', updated_at = now() where id = new.worker_id;
  elsif new.status = 'dismissed' and old.status <> 'dismissed' then
    if not exists (
      select 1 from worker_incidents
      where worker_id = new.worker_id and status = 'confirmed_flag' and id <> new.id
    ) then
      update workers set clearance_status = 'cleared', updated_at = now() where id = new.worker_id;
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function recompute_worker_clearance() returns trigger as $$
declare all_ok boolean;
begin
  select not exists (
    select 1 from worker_credentials where worker_id = new.worker_id and status <> 'approved'
  ) into all_ok;

  if all_ok and not exists (
    select 1 from worker_incidents where worker_id = new.worker_id and status = 'pending_review'
  ) then
    update workers set clearance_status = 'cleared', updated_at = now()
      where id = new.worker_id and clearance_status = 'pending_clearance';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

-- ---------------------------------------------------------------------
-- T1.4: protect_order_financial_fields trigger
-- ---------------------------------------------------------------------
create or replace function protect_order_financial_fields() returns trigger as $$
begin
  if not (auth_has_role('station_owner') or auth_has_role('wasa_admin')) then
    if new.subtotal is distinct from old.subtotal
       or new.delivery_fee is distinct from old.delivery_fee
       or new.total_amount is distinct from old.total_amount
       or new.jugs_ordered is distinct from old.jugs_ordered
       or new.station_id is distinct from old.station_id then
      raise exception 'Drivers may not modify order financial or station details.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_protect_order_financial_fields on orders;
create trigger trg_protect_order_financial_fields
  before update on orders
  for each row execute function protect_order_financial_fields();

-- ---------------------------------------------------------------------
-- T1.5: accreditation_status staleness fix
-- ---------------------------------------------------------------------
create or replace function recompute_accreditation() returns trigger as $$
declare
  all_ok boolean;
begin
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

-- ---------------------------------------------------------------------
-- T1.6: bulletin author spoofing protection
-- ---------------------------------------------------------------------
create or replace function validate_bulletin_author() returns trigger as $$
begin
  if new.posted_by <> auth.uid() then
    raise exception 'posted_by must match the authenticated user.';
  end if;

  if not exists (
    select 1 from memberships
    where profile_id = auth.uid() and role = new.author_role and status = 'active'
  ) then
    raise exception 'author_role does not match an active membership for this account.';
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists trg_validate_bulletin_author on bulletins;
create trigger trg_validate_bulletin_author
  before insert on bulletins
  for each row execute function validate_bulletin_author();

drop policy if exists bulletins_admin_insert on bulletins;
create policy bulletins_admin_insert on bulletins for insert
  with check (auth_has_role('wasa_admin') and posted_by = auth.uid());

drop policy if exists bulletins_member_insert on bulletins;
create policy bulletins_member_insert on bulletins for insert
  with check (
    category in ('event', 'discussion')
    and (auth_has_role('station_owner') or auth_has_role('driver'))
    and posted_by = auth.uid()
  );
