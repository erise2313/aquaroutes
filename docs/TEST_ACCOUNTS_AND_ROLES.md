# GenTri: WASA — test accounts and what each role can access

Last updated 18 October 2026. For testing only — these accounts live in the
project's database (`kdptnxvspqunjngaduok`) and must never be used for real
people.

- Public website: https://gentri-wasa.web.app
- Admin portal: https://gentri-wasa-admin.web.app
- App: `GenTriWASA-arm64-v8a.apk` (Desktop\GenTriWASA-APK)

## Test accounts

All emails end in `@gentriwasa.test`.

| Email | Password | Role | Name | State |
|---|---|---|---|---|
| admin@ | Admin123! | WASA officer | WASA Admin | Active |
| admin2@ | Admin123! | WASA officer | Rosa Mendoza | Active |
| owner1@ | Owner123! | Station owner | Juan Dela Cruz | Buenavista Water Refilling Station — accredited, invite code `BUENAV1` |
| owner2@ | Owner123! | Station owner | Maria Santos | Navarro Springs Water Station — accredited, invite code `NAVSPR1` |
| owner3@ | Owner123! | Station owner | Elena Ramos | Tejero Aqua Station — **not accredited**, all 8 permits waiting for upload, invite code `TEJERO1` |
| driver1@ | Driver123! | Driver | Pedro Reyes | Buenavista — **flagged** (confirmed incident) |
| driver2@ | Driver123! | Driver | Ana Cruz | Navarro Springs — **flagged** (confirmed incident) |
| driver3@ | Driver123! | Driver | Carlo Bautista | Buenavista — cleared, credentials approved |
| driver4@ | Driver123! | Driver | Joy Villanueva | Navarro Springs — cleared, credentials approved |
| customer1@ | Customer123! | Customer | Liza Fernandez | Active, has demo orders |
| customer2@ | Customer123! | Customer | Ramon Garcia | Active, no orders yet |
| suspended@ | Customer123! | Customer | Susana Lim | **Suspended** |

Which account for which test:

- **Assigning a driver** — sign in as owner1 or owner2 and assign driver3 or
  driver4. driver1 and driver2 are flagged, so assigning them is refused
  (that is the "flagged driver not assignable" case).
- **Lifting a flag / appeals** — driver1 or driver2. Either the driver
  appeals (app → Driver Profile → the incident → Appeal this), or an
  officer lifts it (Admin → Workers → All workers → the driver → Lift flag).
- **Accreditation from the start** — owner3 uploads permits in Permit
  vault; an officer reviews them in Admin → Permits.
- **One customer can't see another's orders** — place an order as
  customer2, then sign in as customer1: it is not in customer1's Orders.
- **Suspended account** — sign in as suspended@: the app shows "account
  suspended" instead of the home screen, and ordering is refused. An officer
  can reactivate it in Admin → Users.
- **Two officers** — admin@ sees admin2@ in Users and can suspend them, but
  has no Suspend button on their own row.

The seed scripts are in `supabase/`: `seed_test_accounts.sql` (the first
six accounts), `seed_role_accounts.sql` (the other six, additive and safe to
re-run) and `seed_demo_gaps.sql` (demo orders, jug balances, a flagged
driver).

## What each role can access

### Signed-out visitor

**Website:** every public page — Home, About, How accreditation works, For
station owners, News, Stations directory and each station's page, Verify
accreditation, Jug clearinghouse explainer, Resources, Events, FAQ, Contact,
Privacy policy, Account deletion. Signing in is at `/portal`.

**App:** Home (bulletin and stations), Board, Map, the About WASA hub (About,
Events, FAQ, Contact, For station owners, How accreditation works, Jug
clearinghouse). The Order and Orders tabs ask them to sign in or create an
account — ordering needs an account.

### Customer — app only

On the website, a customer who signs in is told the account type is
app-only.

- **Home** — association notices and nearby accredited stations.
- **Board** — the bulletin: read, react, comment, report a post.
- **Order** — order from an accredited station: product, quantity, delivery
  pin or saved address, optional schedule, jug exchange.
- **Map** — stations on the map, favourites.
- **Orders** — their own orders: status, cancel before it goes out, follow
  the driver on a map while it is out, order again, review the station after
  delivery (rating and comment).
- **My account** — name and phone, delivery addresses, light/dark, change
  password, delete account.
- **Notifications** — order updates (driver on the way, delivered, failed
  delivery with the reason, cancelled).
- **About WASA hub** — from the ⓘ button.

### Driver — app only

On the website, a driver who signs in is told the account type is app-only.

- **Dashboard** — the assigned delivery: navigate, call the station, start
  delivery, complete delivery (empties returned, payment collected, jug
  exchange), **Couldn't deliver** with a reason (the order goes back to the
  station and the customer is told). Route planning for several stops.
- **Driver Profile** — photo, ID and licence uploads for WASA review,
  clearance status, incidents filed against them and **Appeal this** (once
  per incident), switch station by invite code, leave station, account
  settings, and (ⓘ) the About WASA hub.
- **Bulletin board** and **notifications**.

### Station owner — website portal and app

Website: sign in at gentri-wasa.web.app/portal — every section is in the
left sidebar. App: Home, Orders, Products, Track, Board and Profile are tabs;
the rest open from tiles on Home.

- **Home** — invite code (with **issue a new code**), live orders, sales,
  shortcuts to everything below.
- **Orders** — assign to a driver, unassign, cancel; failed deliveries show
  the driver's reason.
- **Products** — what the station sells, prices (not below WASA's floor
  price), availability, delivery fee.
- **Track** — drivers and active deliveries on the map.
- **Drivers** — the roster, vehicle, capacity, idle drivers.
- **Permit vault** — upload permits, see each one's review status and days
  to expiry.
- **Worker registry** — file an incident against a driver, remove a driver;
  sees only the incident reports it filed itself.
- **Hire check** — a driver's clearance and station history before hiring.
- **Clearinghouse** — jug balances with other stations; **propose a
  settlement** (only the station holding the jugs), confirm or reject one
  proposed to it.
- **Board** — post to the bulletin, comment, react.
- **Reviews** *(new)* — the station's ratings and every comment, without the
  reviewers' names.
- **Profile** — owner and station details, location, opening hours, WASA
  resources, About WASA hub, account settings.

### WASA officer — admin portal (website) and app

Website: gentri-wasa-admin.web.app. App: Overview, Stations and Workers are
tabs; the rest are under More.

- **Overview** — queues needing attention (each tile opens the right tab),
  accreditation and permit analytics, items awaiting review.
- **Stations** — every station, list or map, open/close a station, export.
- **Permits** — the review queue; open a station to approve or reject each
  permit, set expiry, mark a permit required, certify a station manually.
- **Workers** — All workers (open anyone's record: **lift a flag**, confirm
  or dismiss an incident, view/approve/reject credentials), Incidents,
  Credentials (approve in bulk), Appeals (accept or reject).
- **Orders** *(new)* — every order in the association: search by customer,
  phone, station or order number; filter by status and date; open one for
  full details; cancel it while it has not gone out; export.
- **Clearinghouse** *(new)* — every jug balance between stations and every
  settlement; **reject** a disputed settlement (confirming stays with the
  station owed).
- **Bulletin** — posts (pin, edit, delete, hide), reported posts, floor
  prices, containers (jug sizes).
- **Reviews** *(new)* — every review with station and reviewer; filter by
  rating; **remove** an abusive or false review.
- **Events** — create, edit, delete; shown on the website and in the app's
  About WASA hub.
- **Resources** — upload and delete documents for stations.
- **Website** — edit every page section, FAQ and permit name, with history
  and restore.
- **Users** — every account: customers, drivers, owners and officers
  *(customers and officers are new)*; search by name, phone or station;
  suspend or reactivate (not yourself); account deletion requests; export.
- **Activity** — the audit log of who changed what; export.
