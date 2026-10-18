import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'driver_management.dart';
import 'hire_check_screen.dart';
import 'jug_clearinghouse_screen.dart';
import 'merchant_dashboard.dart';
import 'orders_screen.dart';
import 'permit_vault_screen.dart';
import 'worker_registry_screen.dart';
import 'tracking_screen.dart';
import 'merchant_profile_screens.dart';
import 'products_screen.dart';
import 'station_reviews_screen.dart';
import 'team_screen.dart';
import '../../providers/app_theme_provider.dart';
import '../../web_router.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/responsive_nav_shell.dart';
import '../public/bulletin_board_screen.dart';

/// Station owner portal shell.
class MerchantNavigation extends StatelessWidget {
  const MerchantNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    // Pinned to the app's own theme rather than inheriting the root one.
    // main.dart drives the root theme from the website's dark-mode toggle, and
    // these screens are written against AppPalette -- without this, a visitor
    // who switched the public site to dark and then signed in as a station
    // owner got white cards and grey text on a dark page. Screens pushed from
    // here need appRoute() (screens/app_route.dart) to keep it.
    return Consumer(
      builder: (context, ref, _) {
        final theme = appThemeDataFor(ref.watch(appThemeProvider), MediaQuery.platformBrightnessOf(context));

        return Theme(
          data: theme,
          child: Builder(
            // A Builder so the shell's controls resolve the Theme above rather
            // than the root one.
            builder: (context) => PortalShell(
              portalName: 'Station portal',
              selectedItemColor: Theme.of(context).colorScheme.primary,
              onBrandTap: () => _leavePortal(context),
              footerActions: [
                const AppThemeToggle(),
                const NotificationBell(),
                PortalAccountMenu(onLeavePortal: kIsWeb ? () => _leavePortal(context) : null),
              ],
              // Wider than the old 1100 prose column: beside a sidebar on a
              // laptop that left a gutter either side of every page.
              maxContentWidth: 1280,
              // On the web every page is in the sidebar. Permit vault, Worker
              // registry, Hire check, Clearinghouse and Drivers used to be
              // reachable only from dashboard tiles. In the app they still
              // are (onPhone: false) -- the app keeps exactly its six tabs.
              //
              // Products sits right after Orders: it's the second thing an
              // owner needs (a station can't take orders until it lists one).
              destinations: const [
                NavShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
                NavShellDestination(icon: Icons.list_alt, label: 'Orders', group: 'Operations'),
                NavShellDestination(icon: Icons.sell_outlined, selectedIcon: Icons.sell, label: 'Products', group: 'Operations'),
                NavShellDestination(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Track', group: 'Operations'),
                NavShellDestination(
                  icon: Icons.groups_outlined,
                  selectedIcon: Icons.groups,
                  label: 'Drivers',
                  group: 'Operations',
                  onPhone: false,
                ),
                NavShellDestination(
                  icon: Icons.badge_outlined,
                  selectedIcon: Icons.badge,
                  label: 'Team',
                  group: 'Operations',
                  onPhone: false,
                ),
                NavShellDestination(
                  icon: Icons.folder_shared_outlined,
                  selectedIcon: Icons.folder_shared,
                  label: 'Permit vault',
                  group: 'Compliance',
                  onPhone: false,
                ),
                NavShellDestination(
                  icon: Icons.report_outlined,
                  selectedIcon: Icons.report,
                  label: 'Worker registry',
                  group: 'Compliance',
                  onPhone: false,
                ),
                NavShellDestination(
                  icon: Icons.person_search_outlined,
                  selectedIcon: Icons.person_search,
                  label: 'Hire check',
                  group: 'Compliance',
                  onPhone: false,
                ),
                NavShellDestination(
                  icon: Icons.swap_horiz,
                  label: 'Clearinghouse',
                  group: 'Network',
                  onPhone: false,
                ),
                NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Board', group: 'Network'),
                NavShellDestination(
                  icon: Icons.star_outline,
                  selectedIcon: Icons.star,
                  label: 'Reviews',
                  group: 'Network',
                  onPhone: false,
                ),
                NavShellDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile', group: 'Account'),
              ],
              pages: const [
                MerchantDashboardScreen(),
                MerchantOrdersScreen(),
                ProductsScreen(),
                TrackingScreen(),
                DriverManagementScreen(),
                TeamScreen(),
                PermitVaultScreen(),
                WorkerRegistryScreen(),
                HireCheckScreen(),
                JugClearinghouseScreen(),
                // The shell supplies the header here, so the wrapper's own
                // AppBar would be a second bar above the feed.
                BulletinBoardScreen(showAppBar: false),
                StationReviewsScreen(),
                MerchantProfileScreen(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Back out to the public site. Only the website build has a router -- in
  /// the app there is nowhere else to go, so the brand mark is inert there.
  void _leavePortal(BuildContext context) {
    if (kIsWeb && GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.home);
    }
  }

}
