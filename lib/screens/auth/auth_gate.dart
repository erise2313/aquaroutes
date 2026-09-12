import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

/// Set via `--dart-define=PORTAL=admin` (deploy_admin_web.ps1) for the
/// WASA-admin-only hosting build -- skips the public marketing site
/// entirely and only lets wasa_admin through after login. Always false in
/// every other build (the default web build, and the mobile app, which
/// never passes this define), so normal behavior is provably unchanged
/// unless this flavor is explicitly built.
const _isAdminPortalBuild = String.fromEnvironment('PORTAL') == 'admin';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _SplashScreen(),
      error: (_, _) => _isAdminPortalBuild ? const _AdminThemed(child: LoginScreen()) : (kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen()),
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
        if (session == null) return _isAdminPortalBuild ? const _AdminThemed(child: LoginScreen()) : (kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen());

        final membershipAsync = ref.watch(currentMembershipProvider);
        return membershipAsync.when(
          loading: () => const _SplashScreen(),
          error: (_, _) => _isAdminPortalBuild ? const _AdminThemed(child: LoginScreen()) : (kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen()),
          data: (membership) {
            if (membership == null) return const _NoActiveMembershipRouter();
            if (_isAdminPortalBuild && membership.role != AppRole.wasaAdmin) {
              return const _AdminThemed(child: _AdminPortalWrongRoleScreen());
            }
            // Admin access on the main site is intentionally being retired
            // now that the dedicated admin portal exists -- a wasa_admin
            // account should never reach AdminNavigation from here, only
            // from gentri-wasa-admin.web.app. Mobile is untouched (this
            // guard only applies to the main *website* build), since admin
            // access there wasn't part of this change.
            if (kIsWeb && !_isAdminPortalBuild && membership.role == AppRole.wasaAdmin) {
              return const _UseAdminPortalScreen();
            }
            switch (membership.role) {
              case AppRole.wasaAdmin:
                return const AdminNavigation();
              case AppRole.stationOwner:
                return const MerchantNavigation();
              case AppRole.driver:
                return kIsWeb ? const MobileOnlyScreen() : const DriverDashboardScreen();
              case AppRole.publicConsumer:
                // A registered customer account -- on mobile, Public Home is
                // auth-aware (shows Account instead of Login/Register) once
                // it detects a session, see public_home_screen.dart. On web,
                // ordering isn't offered at all -- mobile-app-only.
                return kIsWeb ? const MobileOnlyScreen() : const PublicHomeScreen();
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
              const Icon(Icons.admin_panel_settings_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'This portal is for WASA staff only.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Station owners should use gentriwasa.org instead.',
                style: TextStyle(color: Colors.grey),
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

  static const _adminPortalUrl = 'https://gentri-wasa-admin.web.app';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'WASA Admin has moved.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Admin sign-in is no longer available on the main site. Please use the dedicated admin portal instead.',
                style: TextStyle(color: Colors.grey),
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
