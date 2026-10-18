-- =====================================================================
-- patch_trash_part2.sql -- run in the Supabase SQL Editor
--
-- The half of patch_trash.sql the Supabase connector won't apply (it
-- refuses anything that removes rows): restoring from the Trash, deleting
-- an item for good, and the daily job that empties items older than 5
-- days. Run once, after patch_trash.sql. Safe to run again.
-- =====================================================================

create or replace function restore_from_trash(p_trash_id uuid) returns void as $$
declare
  v trash%rowtype;
  item trash%rowtype;
begin
  select * into v from trash where id = p_trash_id and not is_child;
  if not found then
    raise exception 'That item is no longer in the Trash.';
  end if;
  if v.deleted_by is distinct from auth.uid() and not auth_has_role('wasa_admin') then
    raise exception 'Only whoever deleted it, or a WASA officer, can restore this.';
  end if;
  perform set_config('gentri.restoring', 'on', true);
  for item in select * from trash where batch_id = v.batch_id order by is_child, deleted_at loop
    begin
      execute format('insert into %I select * from jsonb_populate_record(null::%I, $1)', item.table_name, item.table_name)
        using item.row_data;
    exception
      when unique_violation then
        if not item.is_child then
          raise exception 'Can''t restore: something with the same details already exists.';
        end if;
      when foreign_key_violation then
        if not item.is_child then
          raise exception 'Can''t restore: what it belonged to has been removed for good.';
        end if;
    end;
  end loop;
  perform set_config('gentri.restoring', 'off', true);
  delete from trash where batch_id = v.batch_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function purge_trash_item(p_trash_id uuid) returns void as $$
declare
  v trash%rowtype;
begin
  select * into v from trash where id = p_trash_id and not is_child;
  if not found then
    raise exception 'That item is no longer in the Trash.';
  end if;
  if v.deleted_by is distinct from auth.uid() and not auth_has_role('wasa_admin') then
    raise exception 'Only whoever deleted it, or a WASA officer, can delete this for good.';
  end if;
  insert into storage_cleanup (bucket, path)
  select 'resources', t.row_data->>'storage_path' from trash t
   where t.batch_id = v.batch_id and t.table_name = 'resources' and coalesce(t.row_data->>'storage_path', '') <> '';
  delete from trash where batch_id = v.batch_id;
end;
$$ language plpgsql security definer set search_path = public;

create or replace function purge_expired_trash() returns integer as $$
declare
  v_batches uuid[];
begin
  select array_agg(distinct batch_id) into v_batches from trash where not is_child and purge_after < now();
  if v_batches is null then
    return 0;
  end if;
  insert into storage_cleanup (bucket, path)
  select 'resources', t.row_data->>'storage_path' from trash t
   where t.batch_id = any(v_batches) and t.table_name = 'resources' and coalesce(t.row_data->>'storage_path', '') <> '';
  delete from trash where batch_id = any(v_batches);
  return coalesce(array_length(v_batches, 1), 0);
end;
$$ language plpgsql security definer set search_path = public;

grant execute on function restore_from_trash(uuid) to authenticated;
grant execute on function purge_trash_item(uuid) to authenticated;

-- Daily, 06:30 Philippine time (22:30 UTC).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and not exists (select 1 from cron.job where jobname = 'gentri-purge-trash') then
    perform cron.schedule('gentri-purge-trash', '30 22 * * *', 'select purge_expired_trash()');
  end if;
end $$;

-- VERIFY -- both should be true
select exists (select 1 from pg_proc where proname = 'restore_from_trash') as restore_ok,
       exists (select 1 from cron.job where jobname = 'gentri-purge-trash') as purge_job_ok;
