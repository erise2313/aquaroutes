-- =====================================================================
-- Officer accounts for each officer role (demo/testing only).
--
--   compliance1@gentriwasa.test  Officer123!  Compliance officer  (Carmen Reyes)
--   workforce1@gentriwasa.test   Officer123!  Workforce officer   (Wilfredo Lim)
--   content1@gentriwasa.test     Officer123!  Content editor      (Cora Bautista)
--   viewer1@gentriwasa.test      Officer123!  Viewer / auditor    (Vilma Santos)
--
-- On the original project these were made in Admin -> Officers by a super
-- admin (create-officer Edge Function), which also asks for a new password
-- at first sign-in. Seeded here so a new project has them straight away,
-- without that first-password step.
--
-- Additive and idempotent: an account whose email already exists is left
-- untouched. Run after seed_role_accounts.sql. Safe to re-run.
-- DO NOT run this against a production project with real users.
-- =====================================================================

do $$
declare
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  v_id uuid;
  acct record;
begin
  for acct in
    select * from (values
      ('compliance1@gentriwasa.test', 'Carmen Reyes',  '09171230011', 'compliance'),
      ('workforce1@gentriwasa.test',  'Wilfredo Lim',  '09171230012', 'workforce'),
      ('content1@gentriwasa.test',    'Cora Bautista', '09171230013', 'content'),
      ('viewer1@gentriwasa.test',     'Vilma Santos',  '09171230014', 'viewer')
    ) as t(email, full_name, phone, officer_role)
  loop
    if exists (select 1 from auth.users where email = acct.email) then
      continue;
    end if;

    v_id := gen_random_uuid();

    -- The handle_new_auth_user trigger creates the matching profiles row.
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      acct.email, crypt('Officer123!', gen_salt('bf')),
      now(), now(), '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', acct.full_name),
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text, jsonb_build_object('sub', v_id::text, 'email', acct.email), 'email', now(), now(), now());

    update profiles set phone_number = acct.phone, privacy_consented_at = now(), privacy_notice_version = 'seed'
     where id = v_id;

    insert into memberships (profile_id, association_id, role, status, officer_role)
    values (v_id, v_association_id, 'wasa_admin', 'active', acct.officer_role);
  end loop;

  -- The full officers seeded earlier, stated explicitly (an empty role
  -- already means full officer).
  update memberships m set officer_role = 'officer'
    from auth.users u
   where u.id = m.profile_id and m.role = 'wasa_admin' and m.officer_role is null
     and u.email in ('admin@gentriwasa.test', 'admin2@gentriwasa.test');
end $$;

-- VERIFY -- one line per officer.
select u.email, m.role, coalesce(m.officer_role, 'officer') as officer_role, m.status
  from auth.users u join memberships m on m.profile_id = u.id
 where m.role in ('wasa_admin', 'wasa_superadmin')
 order by m.role, u.email;
