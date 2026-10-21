import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/membership.dart';
import '../../providers/admin_theme_provider.dart';
import '../../providers/app_state.dart';
import '../admin/admin_navigation.dart';
import '../driver/driver_dashboard.dart';
import '../merchant/merchant_navigation.dart';
import '../public/public_home_screen.dart';
import '../web/mobile_only_screen.dart';
import '../web/org_home_screen.dart';
import '../web/reset_password_screen.dart';
import 'account_suspended_screen.dart';
import 'login_screen.dart';
import 'no_membership_screen.dart';
import '../../constants/portal_build.dart';
import '../help/first_run_tour.dart';
import 'first_password_gate.dart';
import '../staff/staff_navigation.dart';

/// Root routing widget. Restores an existing session on relaunch (the old
/// app always opened LoginScreen regardless of session state) and routes by
/// the resolved AppRole from `memberships`, not a hardcoded 3-way switch on
/// a flat `user_profiles.role` string. Client-side routing here is a UX
/// convenience only -- the real access boundary is Postgres RLS.
///
/// Branches on kIsWeb: the website is the organization/business side
/// (station owner + WASA admin only) with its own public front door
/// (OrgHomeScreen), while driver/public_consumer -- both intentionally
/// mobile-app-only -- get MobileOnlyScreen instead of being routed into
/// screens built assuming a phone. Mobile (!kIsWeb) keeps the exact
/// routing it always had: no session -> the no-login Public Consumer
/// Portal landing page; LoginScreen is reachable from there for the roles
/// that need one.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  /// Nobody signed in. On the website this is the page at /portal, which the
  /// nav bar's Login opens, so it is the sign-in form -- it used to be the
  /// home page, so pressing Login seemed to do nothing. The site's home page
  /// has its own route (/). The app opens on the public customer portal, and
  /// the admin build on its sign-in form.
  static Widget _signedOut(BuildContext context) {
    if (kIsAdminPortalBuild) return const _AdminThemed(child: LoginScreen());
    if (!kIsWeb) return const PublicHomeScreen();
    if (GoRouter.maybeOf(context) == null) return const OrgHomeScreen();
    return LoginScreen(onBackToSite: () => context.go('/'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => _signedOut(context),
      data: (state) {
        // Supabase Flutter auto-detects a password-recovery token in the
        // URL fragment on web with no extra config -- intercept it here
        // before the normal session/membership routing below, since a
        // recovery session still has state.session != null and would
        // otherwise just route into whatever portal this account normally
        // uses instead of letting them actually set a new password.
        if (kIsWeb && state.event == AuthChangeEvent.passwordRecovery) {
          return const ResetPasswordScreen();
        }

        final session = state.session;
        if (session == null) return _signedOut(context);

        final membershipAsync = ref.watch(currentMembershipProvider);
        return membershipAsync.when(
          loading: () => const _SplashScreen(),
          error: (_, _) => kIsAdminPortalBuild ? const _AdminThemed(child: LoginScreen()) : (kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen()),
          data: (membership) {
            if (membership == null) return const _NoActiveMembershipRouter();
            if (kIsAdminPortalBuild && !membership.role.isOfficer) {
              return const _AdminThemed(child: _AdminPortalWrongRoleScreen());
            }
            // Admin access on the main site is intentionally being retired
            // now that the dedicated admin portal exists -- a wasa_admin
            // account should never reach AdminNavigation from here, only
            // from gentri-wasa-admin.web.app. Mobile is untouched (this
            // guard only applies to the main *website* build), since admin
            // access there wasn't part of this change.
            //
            // The phone app is closed to officers too: association
            // administration happens only on the admin portal, a separate
            // site, never in the app customers and drivers install.
            if (!kIsAdminPortalBuild && membership.role.isOfficer) {
              return const _UseAdminPortalScreen();
            }
            // Each role's home shows its welcome tour once (help/first_run_tour.dart).
            Widget withTour(Widget home) => FirstRunTourGate(role: membership.role, child: home);
            switch (membership.role) {
              case AppRole.wasaAdmin:
              case AppRole.wasaSuperadmin:
                // A new officer replaces their temporary password first.
                return FirstPasswordGate(child: withTour(const AdminNavigation()));
              case AppRole.stationStaff:
                // Website and app alike: dispatch is done at a counter as
                // often as on a phone.
                return withTour(const StaffNavigation());
              case AppRole.stationOwner:
                return withTour(const MerchantNavigation());
              case AppRole.driver:
                return kIsWeb ? const MobileOnlyScreen() : withTour(const DriverDashboardScreen());
              case AppRole.publicConsumer:
                // A registered customer account -- on mobile, Public Home is
                // auth-aware (shows Account instead of Login/Register) once
                // it detects a session, see public_home_screen.dart. On web,
                // ordering isn't offered at all -- mobile-app-only.
                return kIsWeb ? const MobileOnlyScreen() : withTour(const PublicHomeScreen());
            }
          },
        );
      },
    );
  }
}

/// Carries the admin portal's own theme (and its light/dark choice) onto the
/// screens shown *before* AdminNavigation exists -- the login screen and the
/// wrong-role notice. Without it, signing in visibly changed the colours,
/// because those screens fell back to the theme the public website uses.
class _AdminThemed extends ConsumerWidget {
  const _AdminThemed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(data: adminThemeDataFor(ref.watch(adminThemeProvider)), child: child);
  }
}

/// Shown on the admin-only portal build when a signed-in account's role
/// isn't wasa_admin -- e.g. a station owner who mistakenly tries to log
/// into the admin link instead of the main site. Offers a sign-out so
/// they aren't stuck on a portal with nothing they can do.
class _AdminPortalWrongRoleScreen extends StatelessWidget {
  const _AdminPortalWrongRoleScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              const Text(
                'This portal is for WASA staff only.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Station owners should sign in on the main GenTri: WASA website instead.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on the main website when a signed-in account turns out to be
/// wasa_admin -- admin access here has been retired in favor of the
/// dedicated admin portal (gentri-wasa-admin.web.app), so normal visitors
/// to the main site can never reach AdminNavigation, and an admin who
/// signs in here by habit is pointed to the right place instead of
/// silently landing in the admin dashboard on the public-facing site.
class _UseAdminPortalScreen extends StatelessWidget {
  const _UseAdminPortalScreen();

  /// Supplied at build time (deploy_web.ps1 passes it from .env) so moving to
  /// a different Firebase project doesn't leave this pointing at the previous
  /// one -- which is exactly what happened when it was a literal: an admin
  /// signing in on the new site was sent to the old project's portal.
  static const _adminPortalUrl = String.fromEnvironment(
    'ADMIN_PORTAL_URL',
    defaultValue: 'https://gentri-wasa-admin.web.app',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                kIsWeb ? 'WASA Admin has moved.' : 'WASA Admin is on the web.',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? 'Admin sign-in is no longer available on the main site. Please use the dedicated admin portal instead.'
                    : 'Officer accounts sign in on the WASA admin portal in a browser, not in the app.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => launchUrl(Uri.parse(_adminPortalUrl), webOnlyWindowName: '_blank'),
                child: const Text('Go to Admin Portal'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// currentMembershipProvider resolved to null -- could mean "no membership
/// row at all" or "a row exists but isn't active" (suspended/revoked by an
/// admin). Distinguishes the two via rawMembershipStatusProvider so a
/// suspended user gets a clear, specific message instead of the generic
/// "not linked to a role yet" copy meant for truly unassigned accounts.
class _NoActiveMembershipRouter extends ConsumerWidget {
  const _NoActiveMembershipRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(rawMembershipStatusProvider);
    return statusAsync.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => const NoMembershipScreen(),
      data: (status) => status == null ? const NoMembershipScreen() : const AccountSuspendedScreen(),
    );
  }
}
