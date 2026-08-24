import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/membership.dart';
import '../../providers/app_state.dart';
import '../admin/admin_navigation.dart';
import '../driver/driver_dashboard.dart';
import '../merchant/merchant_navigation.dart';
import '../public/public_home_screen.dart';
import '../web/mobile_only_screen.dart';
import '../web/org_home_screen.dart';
import 'account_suspended_screen.dart';
import 'no_membership_screen.dart';

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
      error: (_, _) => kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen(),
      data: (state) {
        final session = state.session;
        if (session == null) return kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen();

        final membershipAsync = ref.watch(currentMembershipProvider);
        return membershipAsync.when(
          loading: () => const _SplashScreen(),
          error: (_, _) => kIsWeb ? const OrgHomeScreen() : const PublicHomeScreen(),
          data: (membership) {
            if (membership == null) return const _NoActiveMembershipRouter();
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
