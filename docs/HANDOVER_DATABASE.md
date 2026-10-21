# Moving GenTri WASA to a new Supabase and Firebase account

This sets up a copy of the system under another account (the association's
own, or a separate one for testers). The database part is one SQL file; the
rest is a short list of dashboard steps SQL cannot do.

**Files**

| File | What it is |
|---|---|
| `supabase/setup_new_environment.sql` | **Run this one.** The whole database plus test accounts and demo data. |
| `supabase/reset_and_rebuild.sql` | The database only, no accounts or data (for a clean real launch). |
| `supabase/functions/` | The three server functions (create-officer, delete-account, route-optimize). |
| `docs/TEST_ACCOUNTS_AND_ROLES.md` | Every test login and what each role can do. |

The SQL **does not** copy what testers have entered on the current project
(their orders, uploaded permits, photos). It builds a fresh copy with the
standard test accounts and demo data. To carry over the real data instead,
see "Keeping the current data" at the end.

---

## 1. Supabase (about 20 minutes)

1. **Create the project.** supabase.com → New project. Region: Southeast
   Asia (Singapore). Save the database password somewhere safe.
2. **Run the SQL.** SQL Editor → New query → paste all of
   `setup_new_environment.sql` → Run. It takes a minute or two. The last
   result is a check table; each value should match the "expect" in its
   name. If it times out, run the whole file again; it is safe to repeat.
3. **Email sign-in.** Authentication → Sign In / Providers → Email:
   - turn **Confirm email** OFF (testers sign up and use the app at once).
4. **Web addresses.** Authentication → URL Configuration:
   - Site URL: the new public website address (from step 2.3 below).
   - Redirect URLs: add both the website and the admin portal addresses,
     each followed by `/**`.
5. **Emails (password reset).** The built-in email sender only delivers to
   members of the Supabase team and only a few per hour. For testers to get
   reset emails, set up your own sender under Authentication → Emails →
   SMTP Settings (for example a Gmail app password, Brevo or Resend).
6. **Server functions.** Install the Supabase CLI once, then from the
   project folder:
   ```
   supabase login
   supabase link --project-ref <new-project-ref>
   supabase functions deploy create-officer
   supabase functions deploy delete-account
   supabase functions deploy route-optimize
   ```
   They need no extra secrets: Supabase provides the project URL and key
   automatically. `route-optimize` optionally takes `ORS_API_KEY` or
   `OSRM_BASE_URL` (Edge Functions → Secrets); without them it uses the
   free public road-routing service.
7. **Keys for the app.** Project Settings → API Keys: copy the **Project
   URL** and the **publishable key** (`sb_publishable_…`). Never use the
   secret key in the app.

Nothing else is needed for scheduled jobs (daily permit reminders, trash
clean-up), live updates or file storage. The SQL sets those up.

## 2. Firebase hosting for the two websites (about 15 minutes)

1. console.firebase.google.com → Add project (Analytics not needed).
2. Build → Hosting → Get started, then **Add another site**, so there are
   two sites: one for the public website, one for the admin portal.
3. Choose the site names; they become the addresses, for example
   `wasa-gentri.web.app` and `wasa-gentri-admin.web.app`.
4. In the project folder, edit `.firebaserc`: set `default` to the new
   Firebase project ID, and under `targets` point `main` and `admin` at the
   two new site names.
5. Run `firebase login` with the new account.

## 3. Point the app at the new project

1. Edit `.env` in the project folder:
   ```
   SUPABASE_URL=https://<new-project-ref>.supabase.co
   SUPABASE_ANON_KEY=sb_publishable_...
   ADMIN_PORTAL_URL=https://<new-admin-site>.web.app
   ```
2. In `lib/widgets/station_share_card.dart`, change `publicSiteUrl` to the
   new public website address (it goes into each station's QR code).
3. Deploy the websites: `.\deploy_web.ps1` then `.\deploy_admin_web.ps1`.
4. Build the APK: `flutter build apk --release --split-per-abi` and share
   `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (works on
   almost every phone; `armeabi-v7a` is for very old ones).

**Before a public release, the association should decide** (these can't
be changed later without reinstalling): the app's package name
(currently `com.example.aquaroutecapstone` in `android/app/build.gradle.kts`)
and the signing key. For tester builds the current ones are fine.

## 4. Check it works

Sign in with these (all passwords in `docs/TEST_ACCOUNTS_AND_ROLES.md`):

- `superadmin1@gentriwasa.test` on the admin portal → Officers list shows.
- `owner1@gentriwasa.test` on the website → Station Dashboard with orders.
- `customer1@gentriwasa.test` in the app → place an order.
- `driver1@gentriwasa.test` in the app → the order appears once owner1
  assigns it.

**Change the test passwords** (or delete the test accounts) before real
people use the system. They are published in the test documents.

---

## Keeping the current data instead (optional)

To move the testers' actual data (accounts, orders, permits) rather than
starting fresh, copy the database directly. This needs both projects'
database passwords (Project Settings → Database → Connection string).

```
supabase db dump --db-url "<OLD connection string>" -f roles.sql --role-only
supabase db dump --db-url "<OLD connection string>" -f schema.sql
supabase db dump --db-url "<OLD connection string>" -f data.sql --use-copy --data-only
psql --single-transaction --variable ON_ERROR_STOP=1 --file roles.sql --file schema.sql --command "SET session_replication_role = replica" --file data.sql --dbname "<NEW connection string>"
```

(These are Supabase's own "migrate between projects" steps; `psql` comes
with PostgreSQL. If the dump step complains, the Supabase docs page
"Backup and Restore using the CLI" has the current form.) The two
scheduled jobs live outside the copied schemas: after the copy, run the
`cron.schedule` blocks from `reset_and_rebuild.sql` (search for
`cron.schedule`) in the new project's SQL Editor.

Then follow steps 1.3 to 4 above (skip 1.2). Uploaded files (permit
documents, photos) are not in the database: download them from each
Storage bucket on the old project and upload them to the same bucket and
path on the new one.
