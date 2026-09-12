import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_state.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/web/org_home_screen.dart';
import 'screens/web/reset_password_screen.dart';
import 'screens/web/about_screen.dart';
import 'screens/web/account_deletion_screen.dart';
import 'screens/web/contact_screen.dart';
import 'screens/web/events_screen.dart';
import 'screens/web/faq_screen.dart';
import 'screens/web/for_station_owners_screen.dart';
import 'screens/web/how_accreditation_works_screen.dart';
import 'screens/web/jug_clearinghouse_explainer_screen.dart';
import 'screens/web/news_screen.dart';
import 'screens/web/resources_screen.dart';
import 'screens/web/station_detail_screen.dart';
import 'screens/web/stations_directory_screen.dart';
import 'screens/web/verify_accreditation_screen.dart';
import 'widgets/web_nav_bar.dart';

/// Canonical paths for the public website. Kept in one place so the nav bar,
/// the footer and any in-page link all name the same string, and so a typo
/// is a compile error rather than a silent 404.
class WebRoutes {
  WebRoutes._();

  static const home = '/';

  /// The signed-in dashboard. Split out from `/` so the marketing home stays
  /// reachable while signed in -- previously `/` was AuthGate, so a signed-in
  /// owner pressing Home was swapped into the portal with no way back.
  static const portal = '/portal';

  static const about = '/about';
  static const accreditation = '/accreditation';
  static const forOwners = '/for-owners';
  static const news = '/news';
  static const stations = '/stations';
  static const contact = '/contact';
  static const faq = '/faq';
  static const verify = '/verify';
  static const jugClearinghouse = '/jug-clearinghouse';
  static const resources = '/resources';
  static const events = '/events';

  /// Google Play's required "how to delete your account" page.
  static const accountDeletion = '/account-deletion';

  static String station(String id) => '$stations/$id';

  /// Path for each nav destination, so WebNavBar can navigate by route
  /// instead of pushing a widget instance.
  static const forPage = <WebPage, String>{
    WebPage.home: home,
    WebPage.about: about,
    WebPage.howItWorks: accreditation,
    WebPage.forOwners: forOwners,
    WebPage.news: news,
    WebPage.stations: stations,
    WebPage.contact: contact,
    WebPage.faq: faq,
    WebPage.verifyAccreditation: verify,
    WebPage.jugClearinghouse: jugClearinghouse,
    WebPage.resources: resources,
    WebPage.events: events,
  };
}

/// Reuses the website's existing crossfade (widgets/web_page_route.dart) for
/// routed navigation, including its reduce-motion fallback -- switching to
/// URLs shouldn't cost the transition the site already had.
CustomTransitionPage<void> _page(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(enter),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(enter),
          child: child,
        ),
      );
    },
  );
}

/// `/` -- the marketing home, whether or not anyone is signed in.
///
/// It still has to intercept Supabase's password-recovery event first.
/// Recovery links land on the site root with the token in the URL fragment,
/// and AuthGate used to be what caught them here (auth_gate.dart); moving the
/// portal to its own route would otherwise have quietly broken every reset
/// link, since a recovery session looks like a normal one.
class _PublicHome extends ConsumerWidget {
  const _PublicHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRecovery = ref.watch(authStateProvider).value?.event == AuthChangeEvent.passwordRecovery;
    if (isRecovery) return const ResetPasswordScreen();
    return const OrgHomeScreen();
  }
}

/// Router for the public website build only.
///
/// The site previously had exactly one URL: every page was a
/// `Navigator.push`, so nothing could be bookmarked, shared or indexed --
/// on a site whose entire purpose is telling residents which stations are
/// accredited. The mobile app and the admin portal deliberately do NOT use
/// this: admin having shareable URLs would work against keeping it hidden,
/// and the app has no address bar to benefit from them.
///
/// `/` stays [AuthGate] rather than the marketing home page, so the existing
/// role routing (station owner to the merchant portal, driver/customer to
/// the mobile-only notice) keeps working untouched.
GoRouter buildWebRouter() {
  return GoRouter(
    initialLocation: WebRoutes.home,
    routes: [
      GoRoute(path: WebRoutes.home, pageBuilder: (_, _) => _page(const _PublicHome())),
      GoRoute(path: WebRoutes.portal, pageBuilder: (_, _) => _page(const AuthGate())),
      GoRoute(path: WebRoutes.about, pageBuilder: (_, _) => _page(const AboutScreen())),
      GoRoute(path: WebRoutes.accreditation, pageBuilder: (_, _) => _page(const HowAccreditationWorksScreen())),
      GoRoute(path: WebRoutes.forOwners, pageBuilder: (_, _) => _page(const ForStationOwnersScreen())),
      GoRoute(path: WebRoutes.news, pageBuilder: (_, _) => _page(const NewsScreen())),
      GoRoute(
        path: WebRoutes.stations,
        pageBuilder: (_, _) => _page(const StationsDirectoryScreen()),
        routes: [
          GoRoute(
            path: ':id',
            pageBuilder: (_, state) => _page(StationDetailScreen(stationId: state.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(path: WebRoutes.contact, pageBuilder: (_, _) => _page(const ContactScreen())),
      GoRoute(path: WebRoutes.faq, pageBuilder: (_, _) => _page(const FaqScreen())),
      GoRoute(path: WebRoutes.verify, pageBuilder: (_, _) => _page(const VerifyAccreditationScreen())),
      GoRoute(path: WebRoutes.jugClearinghouse, pageBuilder: (_, _) => _page(const JugClearinghouseExplainerScreen())),
      GoRoute(path: WebRoutes.resources, pageBuilder: (_, _) => _page(const ResourcesScreen())),
      GoRoute(path: WebRoutes.events, pageBuilder: (_, _) => _page(const EventsScreen())),
      GoRoute(path: WebRoutes.accountDeletion, pageBuilder: (_, _) => _page(const AccountDeletionScreen())),
    ],
    // A mistyped URL should land somewhere useful rather than on a router
    // stack trace, which is what an unhandled route renders in release.
    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.toString()),
  );
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.home),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore, size: 64),
              const SizedBox(height: 16),
              Text('Page not found', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Nothing lives at $location.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go(WebRoutes.home),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to the home page'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
