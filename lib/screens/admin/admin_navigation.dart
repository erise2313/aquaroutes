import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'activity_screen.dart';
import 'admin_dashboard.dart';
import 'bulletin_editor_screen.dart';
import 'station_accreditation_screen.dart';
import 'user_management_screen.dart';
import 'website_content_screen.dart';
import 'worker_clearance_screen.dart';
import '../../constants/admin_theme.dart';
import '../../providers/admin_queue_provider.dart';
import '../../widgets/responsive_nav_shell.dart';

/// WASA Admin Portal shell.
class AdminNavigation extends ConsumerWidget {
  const AdminNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Badges are best-effort: if the count query fails the tabs simply show
    // no badge rather than the shell failing to render. The screens behind
    // them still surface their own errors.
    final counts = ref.watch(adminQueueCountsProvider).value;

    return Theme(
      data: AdminTheme.themeData,
      // No outer AppBar: every admin page already renders its own
      // AdminPageHeader, and stacking the two produced a second navy bar
      // above it with the gold rule only under the lower one. Sign-out
      // lives in AdminPageHeader instead -- it's the same action on every
      // admin screen, so it belongs with the header, not a bar of its own.
      child: ResponsiveNavShell(
        // Gold reserved for this one "you are here" highlight -- the rest
        // of the admin theme leans on harbor blue, so the seal color stays
        // meaningful instead of being spread across every accent.
        selectedItemColor: AdminTheme.sealGold,
        // Admin screens are lists, maps and charts, not the phone-shaped
        // forms the shell's 1000px default was chosen for -- at that width a
        // desktop admin monitor renders a narrow column with the right half
        // of the screen empty. Merchant keeps the default.
        maxContentWidth: 1440,
        destinations: [
          const NavShellDestination(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Overview'),
          NavShellDestination(
            icon: Icons.verified_outlined,
            selectedIcon: Icons.verified,
            label: 'Stations',
            badgeCount: counts?.pendingPermits,
          ),
          NavShellDestination(
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            label: 'Workers',
            badgeCount: counts?.workerQueue,
          ),
          const NavShellDestination(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Bulletin'),
          const NavShellDestination(icon: Icons.web_outlined, selectedIcon: Icons.web, label: 'Website'),
          const NavShellDestination(icon: Icons.people_outline, selectedIcon: Icons.people, label: 'Users'),
          const NavShellDestination(icon: Icons.history_outlined, selectedIcon: Icons.history, label: 'Activity'),
        ],
        pages: const [
          AdminDashboardScreen(),
          StationAccreditationScreen(),
          WorkerClearanceScreen(),
          BulletinEditorScreen(),
          WebsiteContentScreen(),
          UserManagementScreen(),
          ActivityScreen(),
        ],
      ),
    );
  }
}
