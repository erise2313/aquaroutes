-- 1. The jug clearinghouse is between the two stations only.
--
-- A settlement was always proposed by the station holding the jugs and
-- confirmed by the station that owns them, but officers could also reject a
-- proposal, and either station could escalate a disagreement to WASA. The
-- association decided settlements are the two stations' business: WASA keeps
-- a read-only view for oversight, and a station that disagrees simply
-- rejects the proposal.

-- Only the owning station rejects a proposal (officers no longer can).
create or replace function reject_jug_settlement(p_settlement_id uuid)
returns void
language plpgsql security definer set search_path = public
as $function$
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
    raise exception 'Only the station that owns the jugs can reject this settlement.';
  end if;
  update jug_settlements set status = 'rejected' where id = p_settlement_id;
end;
$function$;

-- Disputes to WASA are retired.
create or replace function dispute_jug_settlement(p_settlement_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $function$
begin
  raise exception 'Jug settlements are between the two stations. If a proposal is wrong, the owning station rejects it and the holder proposes again.';
end;
$function$;

-- No officer (super admins included) changes clearinghouse records. The
-- stations' own writes and the delivery ledger entries pass, since the
-- guard only acts on officers.
create or replace function guard_officer_area()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_role text := auth_officer_role();
  v_area text := tg_argv[0];
begin
  if v_role is null then
    return coalesce(new, old);
  end if;
  if v_area = 'network' then
    raise exception 'The jug clearinghouse is between the two stations; WASA can view it but not change it.';
  end if;
  if officer_area_allowed(v_role, v_area) then
    return coalesce(new, old);
  end if;
  raise exception 'Your officer role (%) can''t change %. Ask a super admin.',
    case v_role when 'compliance' then 'Compliance' when 'workforce' then 'Workforce'
                when 'content' then 'Content' when 'viewer' then 'Viewer' else v_role end,
    case v_area when 'stations' then 'stations, permits or compliance records'
                when 'workers' then 'worker records'
                when 'content' then 'posts, prices or website content'
                when 'accounts' then 'user accounts'
                else 'association settings' end;
end;
$$;

-- 2. Appeals against a suspension.
--
-- A suspended account could only read "contact WASA". It can now send one
-- written appeal at a time from the suspended screen; full officers and
-- super admins (the "accounts" area) reinstate the account or keep it
-- suspended, with a note the person sees.
create table if not exists account_appeals (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles(id) on delete cascade,
  appeal_text text not null check (length(trim(appeal_text)) >= 10),
  status text not null default 'pending' check (status in ('pending', 'reinstated', 'kept_suspended')),
  decision_note text,
  decided_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists account_appeals_profile_idx on account_appeals (profile_id, created_at desc);
alter table account_appeals enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'account_appeals' and policyname = 'account_appeals_self_read') then
    create policy account_appeals_self_read on account_appeals for select using (profile_id = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where tablename = 'account_appeals' and policyname = 'account_appeals_officer_read') then
    create policy account_appeals_officer_read on account_appeals for select using (auth_has_role('wasa_admin'));
  end if;
end $$;

create or replace trigger trg_guard_officer_area before insert or update or delete on account_appeals
  for each row execute function guard_officer_area('accounts');

create or replace function submit_account_appeal(p_text text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  if not exists (select 1 from memberships where profile_id = auth.uid() and status = 'suspended') then
    raise exception 'This account is not suspended.';
  end if;
  if length(trim(coalesce(p_text, ''))) < 10 then
    raise exception 'Explain in a sentence or two why the suspension should be lifted.';
  end if;
  if exists (select 1 from account_appeals where profile_id = auth.uid() and status = 'pending') then
    raise exception 'Your appeal is already with WASA. You will see the decision here.';
  end if;
  insert into account_appeals (profile_id, appeal_text) values (auth.uid(), left(trim(p_text), 1000));
  insert into notifications (profile_id, category, title, body)
  select m.profile_id, 'account', 'Suspension appeal to review',
         coalesce((select full_name from profiles where id = auth.uid()), 'An account') || ' appealed their suspension.'
    from memberships m
   where m.status = 'active'
     and (m.role = 'wasa_superadmin' or (m.role = 'wasa_admin' and coalesce(m.officer_role, 'officer') = 'officer'));
end;
$$;

create or replace function decide_account_appeal(p_appeal_id uuid, p_reinstate boolean, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  a account_appeals%rowtype;
  v_role text := auth_officer_role();
begin
  if v_role is null or not officer_area_allowed(v_role, 'accounts') then
    raise exception 'Only a full officer or a super admin can decide an appeal.';
  end if;
  if length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Write a short note for the person.';
  end if;
  select * into a from account_appeals where id = p_appeal_id for update;
  if not found then
    raise exception 'Appeal not found.';
  end if;
  if a.status <> 'pending' then
    raise exception 'This appeal has already been decided.';
  end if;
  update account_appeals
     set status = case when p_reinstate then 'reinstated' else 'kept_suspended' end,
         decision_note = trim(p_note), decided_by = auth.uid(), decided_at = now()
   where id = p_appeal_id;
  if p_reinstate then
    -- Officer accounts can only be reinstated by a super admin
    -- (guard_membership_change refuses anyone else).
    update memberships set status = 'active' where profile_id = a.profile_id and status = 'suspended';
  end if;
  insert into notifications (profile_id, category, title, body)
  values (a.profile_id, 'account',
          case when p_reinstate then 'Your account has been reinstated' else 'Your appeal was not accepted' end,
          left(trim(p_note), 200));
end;
$$;

revoke all on function submit_account_appeal(text) from public, anon;
revoke all on function decide_account_appeal(uuid, boolean, text) from public, anon;
grant execute on function submit_account_appeal(text) to authenticated;
grant execute on function decide_account_appeal(uuid, boolean, text) to authenticated;
