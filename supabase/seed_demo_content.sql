-- =====================================================================
-- AquaRoute / GENTRI WASA -- DEMO CONTENT SEEDING (demo/testing only)
-- =====================================================================
-- Populates realistic-looking bulletin posts (with reactions and
-- comments), station reviews, and association events so the website has
-- something to look at while testing -- none of this is real content.
--
-- Requires supabase/seed_test_accounts.sql to have been run FIRST (this
-- script looks up its known test accounts/stations by email/name). Also
-- requires supabase/patch_bulletin_comments.sql and
-- supabase/patch_tier1_tier2_features.sql to have been run first (this
-- script writes to bulletin_comments, reviews, and events).
--
-- DO NOT run this against a production project with real users.
-- Paste this whole file into the Supabase SQL Editor and run it. Re-
-- running is safe -- it clears its own prior output first (bulletin posts/
-- reviews/events authored by the test accounts), it does not touch any
-- other data.
-- =====================================================================

do $$
declare
  admin_id uuid;
  owner1_id uuid;
  owner2_id uuid;
  driver1_id uuid;
  customer1_id uuid;
  v_association_id uuid := '00000000-0000-0000-0000-000000000001';
  station1_id uuid;
  station2_id uuid;
  post_ids uuid[] := array[]::uuid[];
  p_id uuid;
begin
  select id into admin_id from auth.users where email = 'admin@gentriwasa.test';
  select id into owner1_id from auth.users where email = 'owner1@gentriwasa.test';
  select id into owner2_id from auth.users where email = 'owner2@gentriwasa.test';
  select id into driver1_id from auth.users where email = 'driver1@gentriwasa.test';
  select id into customer1_id from auth.users where email = 'customer1@gentriwasa.test';

  if admin_id is null or owner1_id is null or customer1_id is null then
    raise exception 'Test accounts not found -- run supabase/seed_test_accounts.sql first.';
  end if;

  select id into station1_id from water_stations where invite_code = 'BUENAV1';
  select id into station2_id from water_stations where invite_code = 'NAVSPR1';

  -- -------------------------------------------------------------------
  -- 0. Idempotency: clear this script's own prior output before re-seeding.
  -- -------------------------------------------------------------------
  delete from bulletins where posted_by in (admin_id, owner1_id, owner2_id, driver1_id);
  delete from reviews where profile_id in (customer1_id, driver1_id, owner2_id);
  delete from events where created_by = admin_id;

  -- -------------------------------------------------------------------
  -- 1. Bulletin posts -- mix of categories, a couple pinned, varied dates.
  -- -------------------------------------------------------------------
  insert into bulletins (id, association_id, category, title, body, is_pinned, posted_by, author_name, author_role, author_station_name, created_at) values
    (gen_random_uuid(), v_association_id, 'announcement', 'General Assembly moved to next month',
     'Heads up to all member stations: the Q1 General Assembly has been moved from this weekend to the third Saturday of next month, same venue. Attendance sheets will be collected at the door for compliance records.',
     true, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '2 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'New online accreditation verification tool is live',
     'Residents can now confirm whether a station is really WASA-accredited directly on our website under "Verify Accreditation" -- no more guessing based on a sticker on the door.',
     true, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '5 days'),
    (gen_random_uuid(), v_association_id, 'price_change', 'Floor price for alkaline water adjusted',
     'Effective this week, the association floor price for alkaline water has been adjusted to reflect rising filter/mineral costs. All member stations offering alkaline water must update their listed price to stay compliant.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '9 days'),
    (gen_random_uuid(), v_association_id, 'event', 'Water Safety & Sanitation Seminar -- register now',
     'DOH-accredited speakers will walk through updated sanitation standards for refilling stations. Free for all accredited member stations, one slot per station. Message the association office to reserve a seat.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '12 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'Buenavista Water Refilling Station now offering alkaline water',
     'We just completed our alkaline certification! Buenavista Water Refilling Station now offers alkaline water alongside our regular purified line. Same delivery area, same drivers.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '3 days'),
    (gen_random_uuid(), v_association_id, 'discussion', 'Anyone else seeing more bulk orders this month?',
     'Curious if other stations are seeing the same pattern -- our bulk (10+ jug) orders are up noticeably this month. Wondering if it is a barangay-wide thing or just us.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '6 days'),
    (gen_random_uuid(), v_association_id, 'announcement', 'Navarro Springs temporary schedule change this week',
     'Due to a scheduled water district maintenance in our area, Navarro Springs Water Station will have limited delivery slots this Thursday and Friday. Orders placed those days may be scheduled for Saturday instead.',
     false, owner2_id, 'Maria Santos', 'station_owner', 'Navarro Springs Water Station', now() - interval '1 days'),
    (gen_random_uuid(), v_association_id, 'discussion', 'Reminder: always return empty jugs to the driver',
     'Small reminder from the road -- returning your empty jugs directly to the driver (instead of leaving them out) really speeds up the next delivery round. Appreciate everyone who already does this!',
     false, driver1_id, 'Pedro Reyes', 'driver', 'Buenavista Water Refilling Station', now() - interval '4 days'),
    (gen_random_uuid(), v_association_id, 'event', 'Barangay Buenavista I clean water drive -- volunteers welcome',
     'Partnering with the barangay for a community clean water awareness drive next weekend. Looking for a few volunteers to help hand out flyers about spotting unlicensed "colorum" water sellers.',
     false, owner1_id, 'Juan Dela Cruz', 'station_owner', 'Buenavista Water Refilling Station', now() - interval '10 days'),
    (gen_random_uuid(), v_association_id, 'price_change', 'Purified water floor price unchanged for this quarter',
     'Following the quarterly review, the association floor price for purified water remains unchanged. Mineral and alkaline floor prices were adjusted -- see the pinned post above for alkaline.',
     false, admin_id, 'WASA Admin', 'wasa_admin', null, now() - interval '14 days');

  -- -------------------------------------------------------------------
  -- 2. Reactions + comments on a few posts, from the other test accounts,
  --    so the interaction UI has visible data.
  -- -------------------------------------------------------------------
  for p_id in select id from bulletins where posted_by in (admin_id, owner1_id, owner2_id, driver1_id) order by created_at desc limit 5
  loop
    insert into bulletin_reactions (bulletin_id, profile_id)
    values (p_id, customer1_id)
    on conflict do nothing;
    insert into bulletin_reactions (bulletin_id, profile_id)
    values (p_id, owner2_id)
    on conflict do nothing;
  end loop;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, customer1_id, 'Good to know, thanks for the heads up!'
  from bulletins where posted_by = admin_id order by created_at desc limit 1;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, driver1_id, 'Noted, will let customers know on my route today.'
  from bulletins where title like 'Navarro Springs temporary%' limit 1;

  insert into bulletin_comments (bulletin_id, profile_id, body)
  select id, owner2_id, 'Same here actually -- glad it is not just us.'
  from bulletins where title like 'Anyone else seeing more bulk%' limit 1;

  -- -------------------------------------------------------------------
  -- 3. Station reviews (direct insert, not through submit_station_review's
  --    completed-order check -- this is seed data for display purposes).
  -- -------------------------------------------------------------------
  insert into reviews (station_id, profile_id, rating, comment) values
    (station1_id, customer1_id, 5, 'Fast delivery and the driver was very polite. Water tastes clean too.'),
    (station1_id, owner2_id, 4, 'Good service, occasionally a bit slow during rainy days but understandable.'),
    (station2_id, customer1_id, 5, 'Been ordering here for months, never had an issue.'),
    (station2_id, driver1_id, 4, 'Solid station, easy to coordinate with for cross-station jug returns.');

  -- -------------------------------------------------------------------
  -- 4. Events -- mix of upcoming and past.
  -- -------------------------------------------------------------------
  insert into events (title, description, event_date, location, created_by) values
    ('Q2 General Assembly', 'Quarterly meeting for all accredited member stations -- attendance required for one representative per station.', now() + interval '18 days', 'Barangay Buenavista I Covered Court', admin_id),
    ('Water Safety & Sanitation Seminar', 'DOH-accredited speakers on updated sanitation standards. Free for member stations, one slot each.', now() + interval '9 days', 'General Trias Municipal Hall Function Room', admin_id),
    ('New Station Orientation', 'Orientation session for stations currently going through the accreditation process.', now() + interval '30 days', 'WASA Association Office', admin_id),
    ('Q1 General Assembly', 'Quarterly meeting -- floor price review and worker registry updates.', now() - interval '75 days', 'Barangay Buenavista I Covered Court', admin_id),
    ('Community Clean Water Awareness Drive', 'Joint drive with Barangay Buenavista I to raise awareness about unlicensed water sellers.', now() - interval '20 days', 'Buenavista I Barangay Hall', admin_id);

end $$;
