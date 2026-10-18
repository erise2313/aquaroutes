# Standing up a fresh GenTriWASA environment

Builds a complete, independent Supabase + Firebase environment under a new
account, with no link to any previous one. Written for the evaluation
environment, but the steps are the same for any clean rebuild.

Allow about **90 minutes**. Nothing here touches the existing environment —
it stays live and working throughout, so you can abandon this at any point
with no loss.

---

## 0. Before you start

Create the new Google account first. Everything below is done while signed
in to it, in a browser profile where no other Google account is signed in —
Firebase in particular will silently attach a project to whichever account
is active.

You will need, from the current environment:

- This repository, checked out.
- The OpenRouteService API key, if route guidance is to work. Read it from
  the existing project's Edge Function secrets (**Project Settings →
  Edge Functions → Secrets**). It is not in this repository.

### What does *not* carry over

Four things are **not** copied by any step below. Decide now whether you
need them.

| Not copied | Consequence |
|---|---|
| `auth.users` | Every account is new. Nobody's existing password works. Step 1.4 creates fresh ones. |
| Uploaded files in Storage | Buckets are created empty. Permit documents, station photos, bulletin images and resources all start blank. To keep any, download them from the old project's dashboard and re-upload after step 1.3. |
| Live application data | Orders, permits, reviews, bulletins and favourites all start from the seed scripts only. |
| The project ref and anon key | Both change. **Every APK must be rebuilt and both web targets redeployed** (steps 4–5). Old builds will keep pointing at the old project. |

---

## 1. Supabase

### 1.1 Create the project

**supabase.com → New project.**

- Region **ap-southeast-1 (Singapore)** — same as the current project, and
  the nearest to General Trias.
- Save the database password somewhere durable. It cannot be recovered,
  only reset.

Wait for the project to finish provisioning before continuing.

### 1.2 Build the schema

**SQL Editor → New query.** Paste the whole of:

```
supabase/reset_and_rebuild.sql
```

Run it once. It is ~3,700 lines and takes a minute or two.

This single file is the complete schema: all tables, views, functions,
triggers, RLS policies, the six storage buckets, and the reference data
(barangays, permit type labels, container types). It supersedes the files
in `supabase/migrations/` and `supabase/patch_*.sql`, which are the history
of how the schema was reached rather than a way to rebuild it.

> **Keep it that way.** When you next change the schema, append the change
> to `reset_and_rebuild.sql` as well as writing the migration. The script is
> only useful while it stays current.

Confirm it worked — this should return **46**:

```sql
select count(*) from information_schema.tables where table_schema = 'public';
```

The script also switches on Supabase's **pg_cron** extension and schedules
the daily compliance job (permit and licence reminders, grace period,
lapsing). Confirm it is there — this should return one row:

```sql
select jobname, schedule from cron.job where jobname = 'gentri-daily-compliance';
```

### 1.3 Confirm the storage buckets

**Storage.** Seven buckets should already exist:

| Bucket | Public |
|---|---|
| `avatars` | yes |
| `bulletin-images` | yes |
| `permit-documents` | **no** |
| `resources` | yes |
| `station-photos` | yes |
| `station-reports` | **no** |
| `worker-credentials` | **no** |

`permit-documents`, `worker-credentials` and `station-reports` must be
private. They hold business permits, worker identification and customers'
photos of problems. If either shows as public,
fix it before going further.

### 1.4 Seed accounts and content

Run these two, in order, in the SQL Editor:

```
supabase/seed_test_accounts.sql     -- 1 admin, 2 owners (with stations), 2 drivers, 1 customer
supabase/seed_demo_content.sql      -- bulletins, reactions, comments, reviews, events
supabase/seed_evaluation_data.sql   -- orders in every status, jug balances, a permit awaiting review
```

The fourth file fills the modules the others leave empty. Without it the
order pipeline has nothing in flight, the jug clearinghouse is blank, and
the officer's permit review queue is empty — all of which are
indistinguishable from broken when an evaluator opens them.

`seed_test_accounts.sql` creates working logins directly, so nobody has to
register through the app. The credentials are written at the top of that
file — read them there and write them on paper for the evaluator rather
than pasting them into any document.

### 1.5 Auth settings — the part no SQL script can carry

These are **project configuration**, not schema. `reset_and_rebuild.sql`
cannot set them, and skipping them produces two failures that look like
application bugs.

#### Authentication → URL Configuration

| Field | Set to |
|---|---|
| Site URL | your deployed public website address |
| Redirect URLs | both hosting addresses |

A new project defaults Site URL to `http://localhost:3000`.
`lib/screens/auth/login_screen.dart` calls `resetPasswordForEmail()` without
a `redirectTo`, so it falls back to Site URL — meaning every password reset
email links to localhost. The app still reports "Password reset email sent",
so nothing surfaces the fault.

**Password reset is web-only, by design.** There are no deep-link intent
filters in the Android manifest, and `lib/screens/web/reset_password_screen.dart`
documents this: Supabase Flutter auto-detects the recovery token in the URL
fragment on web, and `AuthGate` turns that into the reset screen. A mobile
user who requests a reset receives a link to the *website*, resets there, and
then signs in on the app. Do not add a custom URL scheme to the redirect
list — nothing is registered to receive it.

#### Authentication → Providers → Email

Turn **Confirm email OFF** for an evaluation environment.

New projects enable it by default, and the built-in SMTP on the free tier is
rate-limited to a few messages per hour and often filtered as spam. The
registration test cases depend on this flow, and an evaluator waiting on a
throttled confirmation email will record a failure that is not one.

The seeded accounts are unaffected either way — `seed_test_accounts.sql`
writes `email_confirmed_at` directly, so all six sign in immediately.

> For a production environment, leave confirmation on and configure a real
> SMTP provider instead.

### 1.6 Collect the keys

**Project Settings → API.** You need two values:

- **Project URL** — `https://<ref>.supabase.co`
- **anon / public key**

The **service role key** is also on that page. It bypasses RLS entirely.
It belongs only in Edge Function secrets. It must never appear in `.env`,
in a `--dart-define`, in this repository, or in any document.

---

## 2. Edge Functions

Two functions must be deployed. With the Supabase CLI:

```bash
supabase link --project-ref <new-ref>
supabase functions deploy route-optimize
supabase functions deploy delete-account
```

Then set the secrets — **Project Settings → Edge Functions → Secrets**:

| Secret | Needed by | Notes |
|---|---|---|
| `ORS_API_KEY` | `route-optimize` | OpenRouteService key. Without it the function falls back to the public OSRM server, which works but is rate-limited. |
| `OSRM_BASE_URL` | `route-optimize` | Optional. Only if you are running your own OSRM instance. |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically —
do not add them by hand.

---

## 3. Firebase

### 3.1 Create the project

**console.firebase.google.com → Add project.** Google Analytics is not
required.

### 3.2 Create two hosting sites

**Hosting → Add another site.** The project needs two, because the public
website and the administration portal are separate builds:

| Purpose | Site ID |
|---|---|
| Public website | your main site id |
| Admin portal | your admin site id |

### 3.3 Point the repository at them

Edit `.firebaserc` — replace the project id and both site ids:

```json
{
  "projects": { "default": "<new-firebase-project-id>" },
  "targets": {
    "<new-firebase-project-id>": {
      "hosting": {
        "main":  ["<your-main-site-id>"],
        "admin": ["<your-admin-site-id>"]
      }
    }
  }
}
```

Then:

```bash
firebase login        # as the new account
firebase use <new-firebase-project-id>
```

---

## 4. Point the application at the new backend

### Mobile — `.env`

```
SUPABASE_URL=https://<new-ref>.supabase.co
SUPABASE_ANON_KEY=<new anon key>
MAPTILER_KEY=<optional>
```

`.env` is gitignored and must stay that way.

`MAPTILER_KEY` is optional. Without it the app uses OpenStreetMap's own
tile servers, which is a supported configuration — see the comment in
`lib/widgets/app_map_tiles.dart`. Maps work either way.

### Web — `--dart-define`

`flutter_dotenv` is unreliable in web release builds, so the web builds take
their keys on the command line instead. The deploy scripts already do this;
update the values inside them:

- `deploy_web.ps1` — public website, hosting target `main`
- `deploy_admin_web.ps1` — admin portal, hosting target `admin`

The admin build additionally passes `--dart-define=PORTAL=admin`, which is
what `kIsAdminPortalBuild` reads. Do not remove it, or the admin portal will
build as the public site.

---

## 5. Build and deploy

```powershell
.\deploy_web.ps1          # public website  -> hosting target: main
.\deploy_admin_web.ps1    # admin portal    -> hosting target: admin
```

Each prints `Deploy complete!` for its own target. They deploy **one target
each** — running only one leaves the other pointing at the old backend.

Then the Android builds:

```bash
flutter build apk --split-per-abi
```

Output lands in `build/app/outputs/flutter-apk/`. Hand the evaluator
`app-arm64-v8a-release.apk` unless their device is unusually old.

---

## 6. Verify before handing it over

Work through this in order. Each step depends on the one above it.

- [ ] Both web addresses load in a **private** browser window.
- [ ] The public station directory lists the seeded stations.
- [ ] The map draws tiles — on both the website and the app.
- [ ] Sign in to the admin portal with the seeded admin account.
- [ ] Sign in to the station owner dashboard with a seeded owner account.
- [ ] Install the APK on a device that is **not** the development machine.
- [ ] Place an order as a customer, end to end.
- [ ] Assign it to a driver as the owner, and complete it as the driver.
- [ ] Confirm the customer could see the delivery while it was in progress.
- [ ] Sign in as one station owner and confirm another station's orders are
      **not** visible. This is the RLS check, and it is worth doing
      deliberately rather than assuming.
- [ ] Favourite a station and confirm it pins to the top of the directory.
- [ ] Register a brand-new account through the app. If it waits on a
      confirmation email, step 1.5 was skipped.
- [ ] Request a password reset and open the link in the email. If it points
      at `localhost`, the Site URL in step 1.5 was not set.
- [ ] Request account deletion as a customer. If it fails, the
      `delete-account` Edge Function was not deployed (step 2).

If the last item fails, `favorite_stations` is missing — confirm step 1.2
ran the appended section at the end of the script.

---

## 7. If you need to go back

Nothing above modifies the existing environment. To return to it:

1. Restore `.env` and `.firebaserc` from git (`git checkout -- .env.example .firebaserc`,
   and put the old values back in `.env`).
2. Restore the old keys in both deploy scripts.
3. Redeploy both web targets and rebuild the APKs.

The old Supabase project and its data are untouched throughout.
