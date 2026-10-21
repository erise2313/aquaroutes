-- Super admins are officers too. A driver's appeal notified wasa_admin
-- accounts only, so a super admin was never told about one.
-- (The delete-account edge function had the same gap and was fixed there.)
create or replace function driver_submit_appeal(p_incident_id uuid, p_text text)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  inc worker_incidents%rowtype;
  v_worker_name text;
begin
  if p_text is null or length(trim(p_text)) < 10 then
    raise exception 'Explain your appeal in a sentence or two.';
  end if;

  select * into inc from worker_incidents where id = p_incident_id for update;
  if not found or inc.worker_id not in (select id from workers where profile_id = auth.uid()) then
    raise exception 'Incident not found.';
  end if;
  if inc.status <> 'confirmed_flag' then
    raise exception 'Only a confirmed incident can be appealed.';
  end if;
  if inc.appeal_status is not null then
    raise exception 'This incident has already been appealed.';
  end if;

  update worker_incidents
     set appeal_text = trim(p_text), appeal_status = 'pending', appeal_submitted_at = now()
   where id = p_incident_id;

  select full_name into v_worker_name from workers where id = inc.worker_id;
  insert into notifications (profile_id, category, title, body)
  select m.profile_id, 'worker', 'Driver appeal to review', coalesce(v_worker_name, 'A driver') || ' has appealed a flag.'
    from memberships m
   where m.role in ('wasa_admin', 'wasa_superadmin') and m.status = 'active';
end;
$function$;
