-- The owner's Worker Registry listens to `workers` live, but only orders and
-- notifications were published to Realtime, so the subscription failed and
-- the screen spun forever. RLS still decides which rows each person
-- receives (an owner: their own station's workers).
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'workers') then
    alter publication supabase_realtime add table workers;
  end if;
end $$;
