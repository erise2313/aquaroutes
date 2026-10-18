import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_screen.dart';
import 'admin_clearinghouse_screen.dart';
import 'admin_dashboard.dart';
import 'admin_officers_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reviews_screen.dart';
import 'bulletin_editor_screen.dart';
import 'events_admin_screen.dart';
import 'permit_queue_screen.dart';
import 'resources_admin_screen.dart';
import 'station_accreditation_screen.dart';
import 'user_management_screen.dart';
import 'website_content_screen.dart';
import 'worker_clearance_screen.dart';
import '../../providers/admin_theme_provider.dart';
import '../../providers/app_state.dart';
import '../../models/membership.dart';
import '../../providers/admin_queue_provider.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/responsive_nav_shell.dart';

/// WASA Admin Portal shell.
///
/// Every page is in the sidebar, grouped by what it's for. Events, Resources
/// and the permit review queue used to be reachable only from tiles on the
/// Overview, which is where the evaluation's tester got lost.
///
/// Orders, the jug clearinghouse and station reviews were readable by
/// officers in the database but had no page at all, so the association
/// could not look into a complaint, a jug dispute or an abusive review. They
/// sit under Network and Content.
///
/// In the app, Overview, Stations and Workers are tabs and the rest are on
/// "More" -- seven tabs did not fit a phone. The section names are the ones
/// the test cases use (GTW-APP-285), so nothing a tester looks for was
/// renamed.
class AdminNavigation extends ConsumerWidget {
  const AdminNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Badges are best-effort: if the count query fails the items simply show
    // no badge rather than the shell failing to render.
    final counts = ref.watch(adminQueueCountsProvider).value;
    // Officers and Settings are a super admin's alone; the database refuses
    // the changes to anyone else, so plain officers aren't shown the pages.
    final isSuperadmin = ref.watch(currentMembershipProvider).value?.role == AppRole.wasaSuperadmin;
    final theme = adminThemeDataFor(ref.watch(adminThemeProvider));

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => PortalShell(
          portalName: 'Admin portal',
          selectedItemColor: Theme.of(context).colorScheme.primary,
          footerActions: const [_ThemeToggle(), NotificationBell(), PortalAccountMenu()],
          // Admin screens are lists, maps and charts rather than phone-shaped
          // forms, so they get a wider measure than the site's prose column.
          maxContentWidth: 1440,
          destinations: [
            const NavShellDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Overview'),
            const NavShellDestination(
              icon: Icons.verified_outlined,
              selectedIcon: Icons.verified,
              label: 'Stations',
              group: 'Compliance',
            ),
            NavShellDestination(
              icon: Icons.fact_check_outlined,
              selectedIcon: Icons.fact_check,
              label: 'Permits',
              badgeCount: counts?.pendingPermits,
              group: 'Compliance',
              phoneTab: false,
            ),
            NavShellDestination(
              icon: Icons.badge_outlined,
              selectedIcon: Icons.badge,
              label: 'Workers',
              badgeCount: counts?.workerQueue,
              group: 'Compliance',
            ),
            const NavShellDestination(
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              label: 'Orders',
              group: 'Network',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.swap_horiz,
              label: 'Clearinghouse',
              group: 'Network',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.campaign_outlined,
              selectedIcon: Icons.campaign,
              label: 'Bulletin',
              group: 'Content',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.star_outline,
              selectedIcon: Icons.star,
              label: 'Reviews',
              group: 'Content',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.event_outlined,
              selectedIcon: Icons.event,
              label: 'Events',
              group: 'Content',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.folder_open_outlined,
              selectedIcon: Icons.folder,
              label: 'Resources',
              group: 'Content',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.web_outlined,
              selectedIcon: Icons.web,
              label: 'Website',
              group: 'Content',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.people_outline,
              selectedIcon: Icons.people,
              label: 'Users',
              group: 'People',
              phoneTab: false,
            ),
            const NavShellDestination(
              icon: Icons.history_outlined,
              selectedIcon: Icons.history,
              label: 'Activity',
              group: 'People',
              phoneTab: false,
            ),
            if (isSuperadmin) ...const [
              NavShellDestination(
                icon: Icons.admin_panel_settings_outlined,
                selectedIcon: Icons.admin_panel_settings,
                label: 'Officers',
                group: 'Super admin',
                phoneTab: false,
              ),
              NavShellDestination(
                icon: Icons.tune_outlined,
                selectedIcon: Icons.tune,
                label: 'Settings',
                group: 'Super admin',
                phoneTab: false,
              ),
            ],
          ],
          pages: [
            const AdminDashboardScreen(),
            const StationAccreditationScreen(),
            const PermitQueueScreen(),
            const WorkerClearanceScreen(),
            const AdminOrdersScreen(),
            const AdminClearinghouseScreen(),
            const BulletinEditorScreen(),
            const AdminReviewsScreen(),
            const EventsAdminScreen(),
            const ResourcesAdminScreen(),
            const WebsiteContentScreen(),
            const UserManagementScreen(),
            const ActivityScreen(),
            if (isSuperadmin) ...const [AdminOfficersScreen(), AdminSettingsScreen()],
          ],
        ),
      ),
    );
  }
}

/// The portal's own light/dark switch. It doesn't follow the browser on
/// purpose -- see providers/admin_theme_provider.dart.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(adminThemeProvider) == AdminThemeMode.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => ref.read(adminThemeProvider.notifier).toggle(),
    );
  }
}
