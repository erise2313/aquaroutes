-- =====================================================================
-- patch_help_settings.sql -- Phase 6 (help, settings, order steps)
--
--   1. Order step times: when an order was assigned, went out, was
--      delivered or cancelled -- set by the database on each status change,
--      so no app can write or alter them.
--   2. Notification preferences: mute a category. Enforced where
--      notifications are created, so every source respects it. Account and
--      accreditation notices (official, security) can't be muted.
--
-- Idempotent; no drops. Mirrored into reset_and_rebuild.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Order step times
-- ---------------------------------------------------------------------
alter table orders add column if not exists assigned_at timestamptz;
alter table orders add column if not exists out_for_delivery_at timestamptz;
alter table orders add column if not exists delivered_at timestamptz;
alter table orders add column if not exists cancelled_at timestamptz;

create or replace function set_order_step_times() returns trigger as $$
begin
  if tg_op = 'UPDATE' then
    -- Never edited directly: carried over unless the status moves.
    new.assigned_at := old.assigned_at;
    new.out_for_delivery_at := old.out_for_delivery_at;
    new.delivered_at := old.delivered_at;
    new.cancelled_at := old.cancelled_at;
    if new.status is not distinct from old.status then
      return new;
    end if;
  else
    new.assigned_at := null;
    new.out_for_delivery_at := null;
    new.delivered_at := null;
    new.cancelled_at := null;
  end if;

  case new.status
    when 'assigned' then new.assigned_at := now();
    when 'active' then
      new.out_for_delivery_at := now();
      new.assigned_at := coalesce(new.assigned_at, now());
    when 'done' then new.delivered_at := now();
    when 'cancelled' then new.cancelled_at := now();
    when 'pending' then
      -- Unassigned (or a failed delivery put back): the earlier steps no
      -- longer hold.
      new.assigned_at := null;
      new.out_for_delivery_at := null;
    else null;
  end case;
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_set_order_step_times') then
    create trigger trg_set_order_step_times before insert or update on orders
      for each row execute function set_order_step_times();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Notification preferences
-- ---------------------------------------------------------------------
create table if not exists notification_preferences (
  profile_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  category text not null check (category in ('order', 'permit', 'worker', 'bulletin')),
  muted boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (profile_id, category)
);
alter table notification_preferences enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'notification_preferences' and policyname = 'notification_preferences_self_all') then
    create policy notification_preferences_self_all on notification_preferences for all
      using (profile_id = auth.uid())
      with check (profile_id = auth.uid());
  end if;
end $$;

-- Drops a notification its recipient muted. Returning null from a BEFORE
-- INSERT trigger skips the row and nothing else.
create or replace function respect_notification_preferences() returns trigger as $$
begin
  if exists (
    select 1 from notification_preferences p
     where p.profile_id = new.profile_id and p.category = new.category and p.muted
  ) then
    return null;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_respect_notification_preferences') then
    create trigger trg_respect_notification_preferences before insert on notifications
      for each row execute function respect_notification_preferences();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- VERIFY
-- ---------------------------------------------------------------------
select check_name, ok from (values
  ('step time columns', (select count(*) from information_schema.columns where table_name = 'orders'
      and column_name in ('assigned_at', 'out_for_delivery_at', 'delivered_at', 'cancelled_at')) = 4),
  ('step time trigger', exists (select 1 from pg_trigger where tgname = 'trg_set_order_step_times')),
  ('preferences table', exists (select 1 from information_schema.tables where table_name = 'notification_preferences')),
  ('preferences trigger', exists (select 1 from pg_trigger where tgname = 'trg_respect_notification_preferences'))
) as v(check_name, ok);
