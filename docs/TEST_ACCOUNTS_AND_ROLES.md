# GenTri: WASA — test accounts and what each role can access

Last updated 22 October 2026. For testing only — these accounts live in the
testing environment's database and must never be used for real people.

- Public website: https://gentriwasa.web.app
- Admin portal: https://gentriwasa-admin.web.app
- App: `GenTriWASA-arm64-v8a.apk` (the "1 App" folder of the testing package), built 22 October
  2026 for this environment. Installing it over an older build signs you out
  once; sign in again with the accounts below.

**App testers need the website too.** Officer work -- approving a driver's
documents or a station's permits, reports, incidents -- happens only in the
admin portal. When the app is waiting on one of those, sign in to the admin
portal as an officer, finish it, and go back to the app.

The descriptions below are the starting state of the test data. Testing
changes it (orders get delivered, codes get renewed), so expect differences
after others have used the same accounts.

Every screen works in light and dark mode, uses the Atkinson Hyperlegible
typeface, and has a **Text size** setting (Normal, Large, Extra large) under
account settings. The app is in English; the website also has Tagalog
(**EN | TL** in the top bar).

## Test accounts

All emails end in `@gentriwasa.test`.

| Email | Password | Role | Name | State |
|---|---|---|---|---|
| superadmin1@ | Admin123! | WASA super admin | — | Active |
| superadmin2@ | Admin123! | WASA super admin | — | Active |
| admin@ | Admin123! | WASA officer (full) | WASA Admin | Active |
| admin2@ | Admin123! | WASA officer (full) | Rosa Mendoza | Active |
| compliance1@ | Officer123! | Compliance officer | Carmen Reyes | Active |
| workforce1@ | Officer123! | Workforce officer | Wilfredo Lim | Active |
| content1@ | Officer123! | Content editor | Cora Bautista | Active |
| viewer1@ | Officer123! | Viewer (auditor) | Vilma Santos | Active |
| owner1@ | Owner123! | Station owner | Juan Dela Cruz | Buenavista Water Refilling Station — accredited, good standing |
| owner2@ | Owner123! | Station owner | Juan Dela Rosa | Navarro Springs Water Station — listed, **under review**: its sanitary permit is back with the officers |
| owner3@ | Owner123! | Station owner | Elena Ramos | Tejero Aqua Station — **not accredited**, permits waiting for upload |
| owner4@ | Owner123! | Station owner | Rosalinda Santos | Santiago Pure Water — **lapsed**: water quality test expired 45 days ago |
| owner5@ | Owner123! | Station owner | Ernesto Villanueva | Pasong Kawayan Aqua Hub — **lapsed**: business permit expired 60 days ago |
| staff1@ | Staff123! | Station staff | — | Buenavista counter staff |
| driver1@ | Driver123! | Driver | Pedro Reyes | Buenavista — cleared; has customer1's delivery in progress and an assigned one |
| driver2@ | Driver123! | Driver | Ana Cruz | Navarro Springs — **flagged** (confirmed incident); can appeal |
| driver3@ | Driver123! | Driver | Carlo Bautista | Buenavista — cleared, nothing assigned |
| driver4@ | Driver123! | Driver | Joy Villanueva | Navarro Springs — cleared |
| customer1@ | Customer123! | Customer | Liza Fernandez | Orders in every state: pending, assigned, out for delivery, delivered (mostly Buenavista, one Navarro Springs) |
| customer2@ | Customer123! | Customer | Ramon Garcia | Active, no orders yet |
| suspended@ | Customer123! | Customer | Susana Lim | **Suspended** |
| disposable@ | Disposable123! | Customer | Delete Me | No orders: delete this one to see an account deletion complete |

Each station has two codes, and they are not interchangeable:

| Station | WASA station ID | Driver invite code | Staff code |
|---|---|---|---|
| Buenavista | GW-STN-2026-0001 | **BUENAV1** | **STAFFBV** |
| Navarro Springs | GW-STN-2026-0002 | **NAVSPR1** | **STAFFNV** |
| Tejero | GW-STN-2026-0003 | **TEJERO1** | **STAFFTJ** |
| Santiago (lapsed) | GW-STN-2026-0004 | **SANTGO1** | **STAFFSG** |
| Pasong Kawayan (lapsed) | GW-STN-2026-0005 | **PKAWAY1** | **STAFFPK** |

Every station has a permanent WASA station ID (GW-STN-year-number) and every
driver a worker code (GW-WRK-year-number), so two with the same name can be
told apart. Driver and staff codes are typed in upper case; O/0 and I/1 are
treated as the same.

These are the starting codes; none expire until an owner issues a new one. A code issued anew
expires after 7 days. Drivers register with the driver code; staff register
with the staff code. Entering the wrong kind is refused with a message naming
the right one. The owner's dashboard shows both (the card is titled "DRIVER
INVITE CODE", with the staff code under it); Team also shows the staff code,
and the Worker Registry share icon shows the driver code.

Starting data at a glance:

- **Products:** Buenavista sells purified and alkaline (slim and round
  5-gal, 1-gallon, 350 mL bottle, a new slim jug); Navarro Springs purified
  and mineral (slim and round 5-gal, 500 mL bottle); Tejero purified.
- **Clearinghouse:** Buenavista holds 8 of Navarro's slim jugs and has
  proposed returning 6 (owner2 confirms or rejects); Navarro holds 5 of
  Buenavista's round jugs and has proposed returning 3 (owner1 confirms or
  rejects).
- **Officers' queue:** Navarro's sanitary permit is waiting for review.
- **Lapsed stations:** Santiago Pure Water and Pasong Kawayan Aqua Hub were
  accredited, then a required permit expired more than 30 days ago. They
  are still listed and take orders, but show LAPSED, have no Accredited
  badge and are hidden while "Accredited only" is on. Uploading a renewed
  permit and having an officer approve it restores the accreditation.
- **Board:** posts with reactions and comments, reviews and an event.

The whole database, accounts and data included, is built by
`supabase/setup_new_environment.sql` (see `docs/HANDOVER_DATABASE.md`).

## What each role can access

### Signed-out visitor

**Website:** Home, About, How accreditation works, For station owners, News,
Stations directory and each station's page, Verify accreditation, Jug
clearinghouse explainer, **Safe drinking water** *(new)*, Resources, Events,
FAQ, Contact, Privacy policy, Account deletion. Signing in is at `/portal`.

- **Station pages** *(new)* show the station's standing in words with a
  colour and icon, its last passed water test, how long its sanitary permit
  runs, when it joined, and a **New member** label for 90 days after
  accreditation.
- **Directory** *(new)* shows accredited stations only by default (switch off
  "Accredited only" to see all), accredited first, in an order that changes
  daily so no station is always on top.
- **Verify** *(new wording)* — a station that isn't listed reads "This station
  is not listed with GenTri WASA", in neutral colours; a listed but
  unaccredited station says so plainly.

**App:** Home, Board, Map, the About WASA hub (now with **Safe Drinking
Water**). Ordering needs an account.

### Customer — app only

- **Home** — **My station** *(new)*: the station they order from most, with
  **Order again**; association notices; accredited stations.
- **Map** — "Accredited only" on by default *(new)*; a station's sheet shows
  its association record and **Report a problem to WASA** *(new)*.
- **Order**, **Board** — as before.
- **Orders** — each order shows its steps *(new)*: Placed → Assigned → Out
  for delivery → Delivered, with times; cancel before it goes out; follow
  the driver; order again; rate the station; **Report a problem to WASA**
  *(new)* with an optional photo.
- **Account** — notification switches *(new)*, text size, Help and the
  welcome tour *(new)*, **Trash** *(new)*: their deleted comments and
  addresses for 5 days, with Restore; password, delete account.

### Driver — app only

As before (deliveries, failed delivery with a reason, clearance, appeals).
New: licence upload asks for the expiry date, with a reminder before it
lapses; notification switches; Help and welcome tour.

### Station staff *(new role)* — website portal and app

Counter and dispatch staff. Sign up in the app as "Station Staff (counter /
dispatch)" with the station's staff code (e.g. STAFFBV), not the driver code.

- **Home** — live orders.
- **Orders** — assign, unassign, cancel, and **New order** for phone and
  walk-in customers.
- **Track** — drivers on the map.
- **Drivers** — read-only.
- **Board**.

Staff can't change prices, products, permits, drivers, settlements or the
station.

### Station owner — website portal and app

- **Home** — standing callout when a permit needs renewing or has lapsed;
  **Mentoring** card with the mentor (or mentee) station and a call button
  *(new)*; invite code with its expiry.
- **Orders** — **New order** *(new)*: phone orders (pickup or a delivery
  pin) and walk-in sales (recorded as delivered and paid).
- **Products**, **Track**, **Drivers**, **Worker registry**, **Hire check** —
  as before.
- **Costs** *(new)* — private cost calculator: monthly costs and refills
  give the cost per refill and the margin at current prices. Only the owner
  can see it — not WASA.
- **Team** *(new)* — staff list, remove staff, staff code with expiry.
- **Permit vault** — "5 of 8 done" progress bar and what each permit is
  *(new)*; reminders 30 and 7 days before expiry.
- **WASA notices** *(new)* — official notices to read and acknowledge;
  compliance cases with a written response.
- **Clearinghouse** — settlements are between the two stations: the holder proposes, the owning station confirms or rejects. No WASA step *(changed)*.
- **Reviews** — now with a **Reports to WASA** tab *(new)*: what customers
  reported about the station, never who; answer in writing.
- **Board** — posting rules shown and ticked before posting *(new)*.
- **Profile** — **station QR code and link** *(new)*: copy, show large, save
  as an image on the website.

### WASA officer — admin portal (website only)

Officers can't use the phone app: signing in there shows "WASA Admin is on
the web" with a link to the admin portal. The public website sends them to
the admin portal too.

**Officer roles** *(new)*. Every officer can see everything; the role decides
what they can change. The server refuses anything else ("Your officer role
(Content) can't change ..."), and buttons for it are hidden.

| Role | Can change |
|---|---|
| Officer (full) | Everything except officers and settings |
| Compliance officer | Stations, permits, notices, cases, customer reports, clearinghouse |
| Workforce officer | Workers, incidents, credentials, appeals |
| Content editor | Bulletin, floor prices, containers, events, resources, website, reviews |
| Viewer (auditor) | Nothing; sees and exports everything |

A limited role sees "You are signed in as a ..." on the Overview. Deleting
accounts needs a full officer or super admin.

What a full officer sees:

- **Overview**, **Stations** (now with standing), **Permits**, **Workers** —
  as before. Opening a station also offers **Pair with a mentor** *(new)*.
- **Notices** *(new)* — send to all stations or one; see who read and
  acknowledged.
- **Cases** *(new)* — a written record per issue: what happened, evidence,
  decision, status; the station is notified and can respond.
- **Reports** *(new)* — customer reports with who filed them, the photo, the
  station's response; set status with a note to the customer; open a case
  from a report. Badge counts new reports.
- **No Orders page** *(changed)* — officers don't see stations' orders.
  An order opens only from a customer's report about it (Reports → **View
  the order**), with the customer's name and phone.
- **Clearinghouse** — view only *(changed)*: balances and settlements for
  oversight; officers can't reject or decide anything there.
- **Users** — **Appeals against suspension** *(new)*: Reinstate or Keep
  suspended, each with a note the person sees. Full officers and super
  admins only.
- **Events** — shows how many are going, and who *(new)*.
- **Website** — now includes the Safe Drinking Water articles *(new)*.
- **Bulletin**, **Reviews**, **Resources**, **Users**, **Activity** — as
  before.
- **Trash** *(new)* — everything anyone deleted in the last 5 days (posts,
  comments, products, events, resources, website items, reviews, addresses,
  floor prices), who deleted it, **Restore** or **Delete for good**. After
  5 days it is removed automatically. Officers can't suspend another officer.
- An officer who owns, staffs or drives for a station can't review that
  station's permits, accreditation or incidents.

### WASA super admin *(new role)* — admin portal

Everything an officer has, plus:

- **Officers** — **Create officer account** *(new)*: name, email and role;
  a temporary password is shown once, and the new officer must choose their
  own at first sign-in. **Promote an existing account** (by email, with a
  role), **Change role**, suspend, end access. The last super admin can't be
  removed.
- **Settings** — grace period before a station lapses (30 days) and invite
  code validity (7 days).
- **Transfer ownership** of a station (on the station's page) — orders,
  permits and jug balances stay with the station.

## Addresses *(new)*

Stations, saved customer addresses and orders now have a written address
beside the map pin: house no. / street / subdivision, barangay (from the
association's list), city (General Trias) and an optional landmark. The
owner and staff see it on each order card, and the driver under "Deliver
to". Phone orders delivered by the station need a typed address as well.
Older saved addresses with only a pin show "Tap to add the street and
barangay".

## Test cases for the new features

| # | Sign in as | Steps | Expected |
|---|---|---|---|
| N1 | owner1 | Orders → New order → Walk-in, 3 × a product → Record sale | Order appears under Done as "Walk-in", paid, no delivery fee |
| N2 | owner1 | Orders → New order → Phone order, no phone number → Add order | Refused: "Enter the caller's phone number" |
| N3 | owner1 | New order → Phone order → Deliver to the customer → pin → Add order | Order in New orders with the delivery fee; assign driver3 |
| N4 | staff1 | Orders → New order → Phone order with a number | Order added at Buenavista |
| N5 | staff1 | Look for Products, Permit vault or Costs | Not offered |
| N6 | customer1 | Orders → a delivered order → Report a problem to WASA → Cloudy + photo → Send | "Report sent"; officers get a notification |
| N7 | admin | Reports | The report from N6 with Liza Fernandez's name, the photo, "Needs attention" |
| N8 | admin | Reports → the report from N6 → View the order | The order with Liza Fernandez's name and phone; there is no Orders page in the sidebar |
| N9 | owner2 | Reviews → Reports to WASA | The report, without the customer's name; Respond in writing works |
| N10 | admin | Reports → open N6 → Resolved with a note, tick "open a compliance case" | customer1 notified with the note; a case appears in Cases |
| N11 | visitor | Website → Stations | Only accredited stations; switching off "Accredited only" also shows Navarro Springs (under review) |
| N12 | visitor | Website → a station's page | Association record: standing, last water test, sanitary permit, member since, New member |
| N13 | visitor | Verify → type "Navarro" | "Listed with WASA, not accredited" with its standing |
| N14 | visitor | Verify → type "Nonexistent" | "This station is not listed with GenTri WASA", neutral colours |
| N15 | visitor | Footer → Safe drinking water | Four articles |
| N16 | admin | Website → Safe Drinking Water → edit an article | Change shows on the website page |
| N17 | admin | Stations → Tejero → Pair with a mentor → Buenavista | Both owners notified; owner1 and owner3 see the Mentoring card |
| N18 | owner3 | Try to change mentor (no control offered) | Only officers can pair |
| N19 | owner1 | Costs → enter rent, power, refills → Save | Cost per refill and margin per product; saved |
| N20 | admin | Look for any station's costs | Not available anywhere |
| N21 | owner1 | Clearinghouse → a proposed settlement owed to Buenavista → Confirm (or Reject) | Balance goes down on Confirm; unchanged on Reject; no WASA step |
| N22 | suspended | Sign in → write an appeal → Send appeal to WASA; admin → Users → Reinstate with a note | "Your appeal is with WASA"; after Reinstate the account opens normally |
| N23 | owner1 | Board → New post | Posting rules shown; Post refused until ticked |
| N24 | owner1 | Website → Events → I'll attend | Count goes up; admin → Events → see who lists Juan Dela Cruz |
| N25 | owner1 | Profile → station QR code → Save as image (website) | PNG downloads; scanning it opens the station's page |
| N26 | customer1 | Home | "My station: Buenavista" with Order again |
| N27 | customer1 | Orders | Each order shows its steps and times |
| N28 | customer1 | Account → switch off Order updates; owner2 assigns/delivers an order | No order notification arrives; switch back on and they do |
| N29 | any role | First sign-in on a device | Three-page welcome tour; Account → Help → "Show the welcome tour again" replays it |
| N30 | owner3 | Permit vault | "0 of N done" progress bar and a description under each permit |
| N31 | superadmin1 | Officers → promote customer2 to officer | customer2 can sign in to the admin portal |
| N32 | admin | Users → try to suspend admin2 | No Suspend button; only a super admin can |
| N33 | superadmin1 | Settings → grace period 30 → 15 | Saved; plain officers have no Settings |
| N34 | staff1 | App sign-up with an expired staff code | Refused; owner1 renews the code in Team |
| N35 | customer1 | Orders → a pending order → Cancel → pick a reason | Cancelled; owner1 notified "Order cancelled by the customer" with the reason |
| N36 | owner1 | Orders → New orders → Reject → pick a reason | customer1 notified "Order cancelled by the station" with the reason |
| N37 | customer1 / owner1 | An order the driver has started | No Cancel button for either; the server refuses it ("The driver has already left...") |
| N38 | owner1 | Home → a tile (e.g. Permit vault) → header Back | Returns to Home; browser Back does the same on the website |
| N39 | customer1 | App: Home → Orders tab → top-bar Back, or the phone's back button | Returns to Home before the app closes |
| N40 | admin | Approve the last required permit of a station | Station becomes accredited, gets the seal and appears in the public directory |
| N41 | owner1 | Clearinghouse | Jugs held both ways show as one net balance; settling more than the net is refused |
| N42 | customer1 | Orders → an assigned order | Driver's name, phone and position on the map |
| T1 | owner1 | Products → remove a product | Confirmation says it stays in Trash for 5 days; Account → Trash lists it with "Removed for good in 5 days" |
| T2 | owner1 | Trash → Restore | Product is back in Products with its price |
| T3 | customer1 | Board → comment, then delete it → Account → Trash → Restore | Comment is back under the post |
| T4 | admin | Board → delete a post with comments and reactions → Trash → Restore | Post comes back with its comments and reactions |
| T5 | admin | Trash | Shows everyone's deleted items and who deleted each; customer1 sees only their own |
| T6 | owner2 | Account → Trash | Doesn't see owner1's deleted product |
| T7 | admin | Resources → delete a PDF → Trash → Delete for good | Gone from Trash; the file is removed from storage |
| T8 | customer2 | Delete account | Their comments and addresses are removed at once, not kept in Trash |
| R1 | superadmin1 | Admin portal → Officers → Create officer account → name, new email, Content editor | "Account created" with a temporary password shown once |
| R2 | the new officer | Sign in to the admin portal with the temporary password | "Choose your password" first; after saving, the Overview opens |
| R3 | content1 | Overview | "You are signed in as a content editor" and what it can change |
| R4 | content1 | Events → New Event → save | Allowed |
| R5 | content1 | Stations, Notices, Cases, Workers, Users | No switch, New notice, Open a case, decision or Suspend buttons |
| R6 | viewer1 | Every section | Can read and export; no buttons that change anything |
| R7 | compliance1 | Permits → approve a pending permit | Allowed; Workers has no decision buttons |
| R8 | workforce1 | Workers → Incidents → Confirm flag | Allowed; Permits has no Approve/Reject |
| R9 | admin | Officers in the sidebar | Not shown; only super admins manage officers |
| R10 | admin | Phone app → sign in | "WASA Admin is on the web" with a link to the admin portal |
| R11 | superadmin1 | Officers → an officer → Change role → Viewer | Role pill changes; that officer's buttons disappear on next load |
| I1 | admin | Stations | Each station shows its WASA station ID; searching "GW-STN-2026-0002" finds Navarro Springs |
| I2 | visitor | Website → Verify → type "GW-STN-2026-0001" | Buenavista Water Refilling Station, accredited |
| I3 | visitor | Website → a station's page | "WASA station ID" in the association record |
| I4 | owner1 | Home | Header shows "WASA station ID GW-STN-2026-0001" |
| I5 | owner1 | Orders → New orders → Assign & accept | Each driver shows a GW-WRK code with the plate |
| A1 | customer1 | Account → Addresses → Add → pin, street, barangay, landmark → Save | The list shows the written address |
| A2 | customer1 | Order → pick the saved address | Street, barangay and landmark fill in |
| A3 | customer1 | Order with the street address blank | Refused: "Enter the house no., street or subdivision" |
| A4 | owner2 | Orders → the new order | The written address under the amount |
| A5 | driver4 | Driver dashboard → the assigned order | The written address under "Deliver to" |
| A6 | owner1 | New order → Phone order → Deliver → pin, no typed address | Refused: "Write the delivery address too" |
| A7 | owner1 | Profile → Station Info → street, barangay, landmark → Save | Saved; the station's page shows the address and landmark; the directory's barangay filter finds it |
| A8 | visitor | Website → Register Your Station | Station address asks for street, barangay, city, landmark |
| L1 | customer1 | Order 51 jugs | Refused: at most 50 per order |
| L2 | owner1 | Drivers → edit capacity to 25 | "Between 1 and 20 jugs" |
| L3 | visitor | Website → Register | Only "Water Station Owner" and "Station Staff" are offered |
| L4 | customer1 | Website → Login | Refused: customers sign in on the mobile app |

Reset the data you changed afterwards if another tester needs the same
starting point (re-running the seed scripts restores the accounts but not
orders or reports).
