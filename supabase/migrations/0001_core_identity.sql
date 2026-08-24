-- Core identity: associations, barangays, profiles, role enum.
-- Replaces the old flat user_profiles.role string with a proper
-- association -> membership model (see 0003_memberships.sql).

create extension if not exists pgcrypto;
create extension if not exists postgis;

create table associations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  province text not null default 'Cavite',
  municipality text not null default 'General Trias',
  created_at timestamptz not null default now()
);

create table barangays (
  id uuid primary key default gen_random_uuid(),
  association_id uuid not null references associations(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (association_id, name)
);

-- One row per authenticated person, 1:1 with auth.users.
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone_number text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create type app_role as enum ('wasa_admin', 'station_owner', 'driver', 'public_consumer');

-- Auto-create a profiles row whenever a new auth user signs up, so callers
-- never have to remember to insert into profiles separately.
create or replace function handle_new_auth_user() returns trigger as $$
begin
  insert into profiles (id, full_name, phone_number)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'phone_number')
    on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger trg_handle_new_auth_user
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- Public bucket for profile avatars -- path convention {profile_id}/avatar.{ext}.
-- Write access restricted to the profile owner (0009_rls.sql); reads go
-- through the public CDN URL since the bucket itself is public.
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;
