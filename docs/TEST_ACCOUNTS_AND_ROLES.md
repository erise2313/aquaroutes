# GenTri: WASA — test accounts and what each role can access

Last updated 18 October 2026. For testing only — these accounts live in the
project's database (`kdptnxvspqunjngaduok`) and must never be used for real
people.

- Public website: https://gentri-wasa.web.app
- Admin portal: https://gentri-wasa-admin.web.app
- App: `GenTriWASA-arm64-v8a.apk` (Desktop\GenTriWASA-APK), built 18 October
  2026 (evening of 19 Oct) with everything below, Trash, cancel reasons and Back included. Uninstall an older copy
  first if Android refuses the update.

Every screen works in light and dark mode, uses the Atkinson Hyperlegible
typeface, and has a **Text size** setting (Normal, Large, Extra large) under
account settings. The interface is in English; Tagalog comes later.

## Test accounts

All emails end in `@gentriwasa.test`.

| Email | Password | Role | Name | State |
|---|---|---|---|---|
| superadmin1@ | Admin123! | WASA super admin | — | Active |
| superadmin2@ | Admin123! | WASA super admin | — | Active |
| admin@ | Admin123! | WASA officer | WASA Admin | Active |
| admin2@ | Admin123! | WASA officer | Rosa Mendoza | Active |
| owner1@ | Owner123! | Station owner | Juan Dela Cruz | Buenavista Water Refilling Station — accredited, good standing |
| owner2@ | Owner123! | Station owner | Juan Dela Rosa | Navarro Springs Water Station — accredited, good standing |
| owner3@ | Owner123! | Station owner | Elena Ramos | Tejero Aqua Station — **not accredited**, permits waiting for upload |
| staff1@ | Staff123! | Station staff | — | Buenavista counter staff |
| driver1@ | Driver123! | Driver | Pedro Reyes | Buenavista — **flagged** (confirmed incident) |
| driver2@ | Driver123! | Driver | Ana Cruz | Navarro Springs — **flagged** (confirmed incident) |
| driver3@ | Driver123! | Driver | Carlo Bautista | Buenavista — cleared |
| driver4@ | Driver123! | Driver | Joy Villanueva | Navarro Springs — cleared |
| customer1@ | Customer123! | Customer | Liza Fernandez | Active, has delivered orders from Navarro Springs |
| customer2@ | Customer123! | Customer | Ramon Garcia | Active, no orders yet |
| suspended@ | Customer123! | Customer | Susana Lim | **Suspended** |

Each station has two codes, and they are not interchangeable:

| Station | Driver invite code | Staff code |
|---|---|---|
| Buenavista | **BUENAV1** | **STAFFBV** |
| Navarro Springs | **XYT856** (until 27 Oct) | **STAFFNV** |
| Tejero | **TEJERO1** | **STAFFTJ** |

Codes as of 20 Oct 2026; none expire except where shown. A code issued anew
expires after 7 days. Drivers register with the driver code; staff register
with the staff code. Entering the wrong kind is refused with a message naming
the right one. The owner's dashboard shows both (the card is titled "DRIVER
INVITE CODE", with the staff code under it); Team also shows the staff code,
and the Worker Registry share icon shows the driver code.

The seed scripts are in `supabase/`: `seed_test_accounts.sql`,
`seed_role_accounts.sql` (additive, safe to re-run) and `seed_demo_gaps.sql`.

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
- **Clearinghouse** — **Dispute with WASA** on a settlement *(new)*.
- **Reviews** — now with a **Reports to WASA** tab *(new)*: what customers
  reported about the station, never who; answer in writing.
- **Board** — posting rules shown and ticked before posting *(new)*.
- **Profile** — **station QR code and link** *(new)*: copy, show large, save
  as an image on the website.

### WASA officer — admin portal (website) and app

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
- **Clearinghouse** — disputed settlements first, with **Decide the
  dispute** *(new)*.
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

- **Officers** — promote an account to officer or super admin by email,
  demote, suspend. The last super admin can't be removed.
- **Settings** — grace period before a station lapses (30 days) and invite
  code validity (7 days).
- **Transfer ownership** of a station (on the station's page) — orders,
  permits and jug balances stay with the station.

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
| N11 | visitor | Website → Stations | Only accredited stations; switching off "Accredited only" shows Tejero |
| N12 | visitor | Website → a station's page | Association record: standing, last water test, sanitary permit, member since, New member |
| N13 | visitor | Verify → type "Tejero" | "Listed with WASA, not accredited" with its standing |
| N14 | visitor | Verify → type "Nonexistent" | "This station is not listed with GenTri WASA", neutral colours |
| N15 | visitor | Footer → Safe drinking water | Four articles |
| N16 | admin | Website → Safe Drinking Water → edit an article | Change shows on the website page |
| N17 | admin | Stations → Tejero → Pair with a mentor → Buenavista | Both owners notified; owner1 and owner3 see the Mentoring card |
| N18 | owner3 | Try to change mentor (no control offered) | Only officers can pair |
| N19 | owner1 | Costs → enter rent, power, refills → Save | Cost per refill and margin per product; saved |
| N20 | admin | Look for any station's costs | Not available anywhere |
| N21 | owner1 | Clearinghouse → a settlement → Dispute with WASA | "Disputed -- with WASA"; officers notified |
| N22 | admin | Clearinghouse → the dispute → Decide | Both owners notified with the decision |
| N23 | owner1 | Board → New post | Posting rules shown; Post refused until ticked |
| N24 | owner1 | Website → Events → I'll attend | Count goes up; admin → Events → see who lists Juan Dela Cruz |
| N25 | owner1 | Profile → station QR code → Save as image (website) | PNG downloads; scanning it opens the station's page |
| N26 | customer1 | Home | "My station: Navarro Springs" with Order again |
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

Reset the data you changed afterwards if another tester needs the same
starting point (re-running the seed scripts restores the accounts but not
orders or reports).
