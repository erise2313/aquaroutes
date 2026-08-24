-- =====================================================================
-- Incremental patch: adds bulletin_comments (website News page comment
-- feature). Additive/corrective -- no data loss. Paste into the Supabase
-- SQL Editor and run once. Safe to re-run.
-- =====================================================================

create table if not exists bulletin_comments (
  id uuid primary key default gen_random_uuid(),
  bulletin_id uuid not null references bulletins(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists bulletin_comments_bulletin_idx on bulletin_comments (bulletin_id);

alter table bulletin_comments enable row level security;

drop policy if exists bulletin_comments_public_read on bulletin_comments;
create policy bulletin_comments_public_read on bulletin_comments for select
  using (true);

drop policy if exists bulletin_comments_self_insert on bulletin_comments;
create policy bulletin_comments_self_insert on bulletin_comments for insert
  with check (profile_id = auth.uid());

drop policy if exists bulletin_comments_self_or_admin_delete on bulletin_comments;
create policy bulletin_comments_self_or_admin_delete on bulletin_comments for delete
  using (profile_id = auth.uid() or auth_has_role('wasa_admin'));
