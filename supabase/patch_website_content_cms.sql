-- =====================================================================
-- Website content management: admin-editable content for the six static
-- website pages (About, FAQ, Contact, For Station Owners, How
-- Accreditation Works, Jug Clearinghouse Explainer), which previously had
-- no admin editor at all -- their copy was hardcoded directly in the
-- Dart widget trees. Follows the exact pattern already proven by
-- `bulletins` (public-read/admin-write RLS + a service + an admin
-- editor screen).
--
-- Also fixes a real, already-drifting bug found while researching this:
-- permit type display labels/condition notes were hardcoded
-- independently in permit_vault_screen.dart, permit_review_screen.dart,
-- and how_accreditation_works_screen.dart -- three separate copies kept
-- in sync only by hand (a recently-added permit type required editing
-- all three). `permit_type_labels` collapses these into one shared,
-- admin-editable source that both the app and the website read.
--
-- Every table is seeded verbatim from the current hardcoded copy, so
-- nothing visibly changes on first deploy -- admin can edit from there.
-- Paste into the Supabase SQL Editor and run once. Safe to re-run.
-- =====================================================================

create table if not exists web_page_sections (
  id uuid primary key default gen_random_uuid(),
  page_key text not null,
  section_key text not null,
  title text,
  body text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now(),
  unique (page_key, section_key)
);

create table if not exists web_content_items (
  id uuid primary key default gen_random_uuid(),
  page_key text not null,
  item_key text not null,
  icon text,
  title text not null,
  body text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

create index if not exists web_content_items_page_item_idx on web_content_items (page_key, item_key, sort_order);

create table if not exists web_faq_entries (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  answer text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

-- One row per permit_type enum value (currently 10). Update-only for
-- admin -- the row set is fixed by the enum, so there's no insert/delete
-- policy, only select/update.
create table if not exists permit_type_labels (
  permit_type permit_type primary key,
  label text not null,
  condition_note text not null,
  sort_order int not null default 0,
  updated_by uuid references profiles(id),
  updated_at timestamptz not null default now()
);

alter table web_page_sections enable row level security;
alter table web_content_items enable row level security;
alter table web_faq_entries enable row level security;
alter table permit_type_labels enable row level security;

create policy web_page_sections_public_read on web_page_sections for select using (true);
create policy web_page_sections_admin_insert on web_page_sections for insert with check (auth_has_role('wasa_admin'));
create policy web_page_sections_admin_update on web_page_sections for update using (auth_has_role('wasa_admin'));
create policy web_page_sections_admin_delete on web_page_sections for delete using (auth_has_role('wasa_admin'));

create policy web_content_items_public_read on web_content_items for select using (true);
create policy web_content_items_admin_insert on web_content_items for insert with check (auth_has_role('wasa_admin'));
create policy web_content_items_admin_update on web_content_items for update using (auth_has_role('wasa_admin'));
create policy web_content_items_admin_delete on web_content_items for delete using (auth_has_role('wasa_admin'));

create policy web_faq_entries_public_read on web_faq_entries for select using (true);
create policy web_faq_entries_admin_insert on web_faq_entries for insert with check (auth_has_role('wasa_admin'));
create policy web_faq_entries_admin_update on web_faq_entries for update using (auth_has_role('wasa_admin'));
create policy web_faq_entries_admin_delete on web_faq_entries for delete using (auth_has_role('wasa_admin'));

create policy permit_type_labels_public_read on permit_type_labels for select using (true);
create policy permit_type_labels_admin_update on permit_type_labels for update using (auth_has_role('wasa_admin'));

-- ---- Seed: About -- "What WASA Does" bullets ----
insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('about', 'what_wasa_does', '', 'Reviews and accredits refilling stations before they can display the WASA verification seal.', 0),
  ('about', 'what_wasa_does', '', 'Maintains a shared worker security registry, so a driver flagged for an incident at one station can''t simply move to another unnoticed.', 1),
  ('about', 'what_wasa_does', '', 'Sets and enforces minimum floor prices to prevent predatory undercutting between member stations.', 2),
  ('about', 'what_wasa_does', '', 'Coordinates the inter-station jug clearinghouse, so reusable 5-gallon containers get settled fairly between stations.', 3)
on conflict do nothing;

-- ---- Seed: FAQ ----
insert into web_faq_entries (question, answer, sort_order) values
  ('Who can order water through GENTRI WASA?', 'Anyone can browse the station directory and community bulletin without an account. Placing an order requires a free customer account, so deliveries are tied to a real, trackable identity rather than anonymous device state.', 0),
  ('How do I know a station is legitimate?', 'Look for the green "WASA Verified" seal on the station directory and map. It only appears once every required permit has been reviewed and approved by a WASA admin -- a station cannot grant itself this seal.', 1),
  ('What permits does a station need to get accredited?', 'A Mayor''s Business Permit, a Sanitary Permit, and an FDA License to Operate are required for every station. Stations offering alkaline water also need an Alkaline Machine Technical Certification and an Alkaline Water Quality Test Report.', 2),
  ('How long does accreditation review take?', 'There''s no fixed timeline -- a WASA admin reviews each uploaded document individually and either approves it or rejects it with a stated reason, so an owner always knows exactly what to fix and can re-upload immediately.', 3),
  ('Can I schedule a delivery instead of ordering ASAP?', 'Yes -- the order form has an ASAP/Scheduled toggle. Choosing Scheduled lets you pick a future date and time for delivery instead of requesting the soonest available driver.', 4),
  ('How do I pay?', 'Cash on delivery. The total (jugs x price, plus delivery fee) is shown before you confirm the order and again when the driver arrives.', 5),
  ('What is the floor price, and why does it exist?', 'WASA sets a minimum price per water type across all member stations, so no station can undercut competitors to the point of predatory pricing. Every station''s price must stay at or above this floor.', 6),
  ('What happens if I have a problem with a driver or station?', 'Station owners can file a security incident against a worker through the shared clearance registry, which follows that worker even if they move to another member station. Residents can reach the association directly through the Contact page.', 7)
on conflict do nothing;

-- ---- Seed: Contact ----
insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('contact', 'address', '[Placeholder] Association Office Address, General Trias, Cavite', 0),
  ('contact', 'hours', '[Placeholder] Office Hours: Monday-Friday, 8:00 AM - 5:00 PM', 1),
  ('contact', 'email', 'contact@gentriwasa.example', 2)
on conflict do nothing;

-- ---- Seed: For Station Owners ----
insert into web_content_items (page_key, item_key, icon, title, body, sort_order) values
  ('for_station_owners', 'benefits', 'verified', 'Official Recognition', 'Accredited stations get the WASA verification seal on the public directory and map.', 0),
  ('for_station_owners', 'benefits', 'security', 'Worker Accountability', 'Screen prospective drivers/helpers against the shared cross-station clearance registry before hiring.', 1),
  ('for_station_owners', 'benefits', 'price_change', 'Fair Pricing Protection', 'Association-wide floor prices protect member stations from predatory undercutting.', 2),
  ('for_station_owners', 'benefits', 'swap_horiz', 'Jug Clearinghouse', 'Settle Slim/Round 5-gallon jug balances with other stations through one shared ledger.', 3)
on conflict do nothing;

insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('for_station_owners', 'requirements_summary', 'Business Permit, Sanitary Permit, FDA License to Operate, a Fire Safety Inspection Certificate, a Water Quality Test Report, and an Operator Training Certificate at minimum -- plus additional certifications if you offer alkaline water or source your own well water.', 0)
on conflict do nothing;

-- ---- Seed: How Accreditation Works -- process steps ----
insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('how_accreditation_works', 'steps', 'Register the station', 'The owner creates an account and registers their station with basic details (name, address, offered water types).', 0),
  ('how_accreditation_works', 'steps', 'Upload required documents', 'Every station uploads its Business Permit, Sanitary Permit, FDA License, Fire Safety Inspection Certificate, Water Quality Test Report, and Operator Training Certificate. Stations offering alkaline water also upload two additional certifications, and WASA may require the NWRB Water Permit/Certificate of Public Convenience for stations sourcing their own well water.', 1),
  ('how_accreditation_works', 'steps', 'WASA reviews each document', 'A WASA admin reviews every uploaded document individually -- approving, or rejecting with a stated reason so the owner knows exactly what to fix.', 2),
  ('how_accreditation_works', 'steps', 'Accreditation is automatic once complete', 'The moment every required document is approved, the station is automatically marked accredited -- no separate manual step, and no way for a station to grant itself accreditation.', 3),
  ('how_accreditation_works', 'steps', 'The colorum-verification seal appears', 'Accredited, WASA-verified stations get the verification seal on the public station directory, so residents can tell a legitimate operator from an unlicensed one at a glance.', 4)
on conflict do nothing;

-- ---- Seed: Jug Clearinghouse Explainer ----
-- Step 1's copy is corrected here (not just copied verbatim) -- it used
-- to describe the old fully-manual recording flow; patch_jug_provenance.sql
-- made this automatic at delivery completion, so the explainer should
-- say that, not the outdated mechanism.
insert into web_page_sections (page_key, section_key, body, sort_order) values
  ('jug_clearinghouse', 'intro', 'Reusable Slim and Round 5-gallon jugs regularly end up at a different station than the one that owns them -- a driver delivers water in one station''s jug, and picks up an empty jug bearing a competitor''s brand. Without a shared system, that jug is effectively lost to its owner. The clearinghouse makes those swaps fair and auditable across the whole association.', 0)
on conflict do nothing;

insert into web_content_items (page_key, item_key, title, body, sort_order) values
  ('jug_clearinghouse', 'steps', 'A jug crosses station lines', 'When a customer exchanges an empty jug at a different station than the one that owns it, the app automatically records who now holds the jug and who it belongs to as soon as the delivery is completed.', 0),
  ('jug_clearinghouse', 'steps', 'The ledger tracks who holds what', 'Every cross-station transfer is logged as a ledger entry -- which station now holds the jug, and which station originally owns it.', 1),
  ('jug_clearinghouse', 'steps', 'Balances net out automatically', 'Instead of settling jug-by-jug, the system nets all transfers between two stations into a single running balance per jug type.', 2),
  ('jug_clearinghouse', 'steps', 'Stations propose and confirm settlement', 'A holder station proposes a settlement to clear its balance; the owner station confirms or rejects it. Confirming atomically posts the offsetting ledger entry, so the balance can''t drift or be double-counted.', 3)
on conflict do nothing;

-- ---- Seed: permit type labels (all 10 known values) ----
insert into permit_type_labels (permit_type, label, condition_note, sort_order) values
  ('business_permit', 'Mayor''s Business Permit', 'Required for every station.', 0),
  ('sanitary_permit', 'Sanitary Permit', 'Required for every station.', 1),
  ('fda_license', 'FDA License to Operate', 'Required for every station.', 2),
  ('fire_safety_certificate', 'Fire Safety Inspection Certificate (BFP)', 'Required for every station.', 3),
  ('water_quality_test_report', 'Water Quality Test Report (DOH)', 'Required for every station.', 4),
  ('operator_training_certificate', 'Operator Training Certificate (CCWRSPO)', 'Required for every station.', 5),
  ('alkaline_tech_cert', 'Alkaline Machine Technical Certification', 'Only required if the station offers alkaline water.', 6),
  ('alkaline_water_test', 'Alkaline Water Quality Test Report', 'Only required if the station offers alkaline water.', 7),
  ('nwrb_water_permit', 'NWRB Water Permit', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 8),
  ('nwrb_certificate_of_public_convenience', 'NWRB Certificate of Public Convenience', 'Required only for stations sourcing their own well water; WASA confirms this per station.', 9)
on conflict (permit_type) do nothing;
