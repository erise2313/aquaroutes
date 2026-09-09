-- Read-only "who did what" feed for the WASA admin portal.
--
-- Every admin mutation in this schema already stamps an actor and a
-- timestamp -- permits.reviewed_by/at, worker_incidents.resolved_by/at,
-- worker_credentials.reviewed_by/at, water_stations.accreditation_override_
-- by/at, and updated_by/at on all four CMS tables. Until now exactly one of
-- those was ever read back (permit_review_screen.dart renders "manually
-- certified by X"), so an admin could not answer "who suspended this
-- account?" or "what did I approve last week?"
--
-- This is a view, not a new audit table: the data is already being written,
-- so logging it a second time would add a write path that could disagree
-- with the records it is supposed to describe. The trade-off is that it only
-- shows the LATEST action per row -- re-reviewing a permit overwrites
-- reviewed_at, so this is an activity feed, not a full history. A real
-- append-only audit log would be a separate change.
--
-- security_invoker = on so the querying user's own RLS applies: admins
-- already have read access to every underlying table and nobody else does,
-- so this view cannot become a way around those policies.

create or replace view admin_activity
with (security_invoker = on) as
select a.actor_id, a.occurred_at, a.category, a.action, a.subject,
       coalesce(pr.full_name, 'Unknown') as actor_name
from (
  select
    p.reviewed_by                              as actor_id,
    p.reviewed_at                              as occurred_at,
    'Permit'                                   as category,
    case p.status::text
      when 'approved' then 'Approved permit'
      when 'rejected' then 'Rejected permit'
      else 'Reviewed permit'
    end                                        as action,
    coalesce(ws.station_name, 'Unknown station') || ' - ' || p.permit_type::text as subject
  from permits p
  left join water_stations ws on ws.id = p.station_id
  where p.reviewed_by is not null and p.reviewed_at is not null

  union all

  select
    wi.resolved_by,
    wi.resolved_at,
    'Worker incident',
    case wi.status::text
      when 'confirmed_flag' then 'Confirmed flag on'
      when 'dismissed' then 'Dismissed incident for'
      else 'Resolved incident for'
    end,
    coalesce(w.full_name, 'Unknown worker')
  from worker_incidents wi
  left join workers w on w.id = wi.worker_id
  where wi.resolved_by is not null and wi.resolved_at is not null

  union all

  select
    wc.reviewed_by,
    wc.reviewed_at,
    'Worker credential',
    case wc.status::text
      when 'approved' then 'Approved credential for'
      when 'rejected' then 'Rejected credential for'
      else 'Reviewed credential for'
    end,
    coalesce(w.full_name, 'Unknown worker') || ' (' || wc.credential_type::text || ')'
  from worker_credentials wc
  left join workers w on w.id = wc.worker_id
  where wc.reviewed_by is not null and wc.reviewed_at is not null

  union all

  select
    ws.accreditation_override_by,
    ws.accreditation_override_at,
    'Accreditation',
    'Manually certified',
    ws.station_name
  from water_stations ws
  where ws.accreditation_override_by is not null and ws.accreditation_override_at is not null

  union all

  select s.updated_by, s.updated_at, 'Website content', 'Edited section', s.page_key || ' / ' || s.section_key
  from web_page_sections s
  where s.updated_by is not null

  union all

  select i.updated_by, i.updated_at, 'Website content', 'Edited item', i.page_key || ' / ' || i.item_key
  from web_content_items i
  where i.updated_by is not null

  union all

  select f.updated_by, f.updated_at, 'Website content', 'Edited FAQ', f.question
  from web_faq_entries f
  where f.updated_by is not null

  union all

  select l.updated_by, l.updated_at, 'Website content', 'Edited permit label', l.permit_type::text
  from permit_type_labels l
  where l.updated_by is not null
) a
left join profiles pr on pr.id = a.actor_id;

comment on view admin_activity is
  'Latest recorded admin action per row, unioned from the actor columns the app already writes. Activity feed, not an append-only audit log.';
