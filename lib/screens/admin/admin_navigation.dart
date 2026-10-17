import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_screen.dart';
import 'admin_dashboard.dart';
import 'bulletin_editor_screen.dart';
import 'events_admin_screen.dart';
import 'permit_queue_screen.dart';
import 'resources_admin_screen.dart';
import 'station_accreditation_screen.dart';
import 'user_management_screen.dart';
import 'website_content_screen.dart';
import 'worker_clearance_screen.dart';
import '../../constants/admin_theme.dart';
import '../../providers/admin_theme_provider.dart';
import '../../providers/admin_queue_provider.dart';
import '../../widgets/account_settings_section.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/responsive_nav_shell.dart';

/// WASA Admin Portal shell.
///
/// Every page is in the sidebar, grouped by what it's for. Events, Resources
/// and the permit review queue used to be reachable only from tiles on the
/// Overview, which is where the evaluation's tester got lost.
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
    final theme = adminThemeDataFor(ref.watch(adminThemeProvider));

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => PortalShell(
          portalName: 'Admin portal',
          selectedItemColor: AdminTheme.harborBlue,
          footerActions: const [_ThemeToggle(), NotificationBell(), _AccountMenu()],
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
              icon: Icons.campaign_outlined,
              selectedIcon: Icons.campaign,
              label: 'Bulletin',
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
          ],
          pages: const [
            AdminDashboardScreen(),
            StationAccreditationScreen(),
            PermitQueueScreen(),
            WorkerClearanceScreen(),
            BulletinEditorScreen(),
            EventsAdminScreen(),
            ResourcesAdminScreen(),
            WebsiteContentScreen(),
            UserManagementScreen(),
            ActivityScreen(),
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

/// An account menu rather than a bare sign-out button, so admins can also
/// change their password.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (value) {
        if (value == 'account') {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Account'),
              contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
              content: const SizedBox(width: 420, child: AccountSettingsSection()),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
              ],
            ),
          );
        } else {
          Supabase.instance.client.auth.signOut();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'account',
          child: ListTile(leading: Icon(Icons.manage_accounts_outlined), title: Text('Account & password')),
        ),
        PopupMenuItem(
          value: 'signout',
          child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out')),
        ),
      ],
    );
  }
}
