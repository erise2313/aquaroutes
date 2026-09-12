import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity_screen.dart';
import 'admin_dashboard.dart';
import 'bulletin_editor_screen.dart';
import 'station_accreditation_screen.dart';
import 'user_management_screen.dart';
import 'website_content_screen.dart';
import 'worker_clearance_screen.dart';
import '../../constants/admin_palette.dart';
import '../../constants/admin_theme.dart';
import '../../providers/admin_theme_provider.dart';
import '../../providers/admin_queue_provider.dart';
import '../../widgets/account_settings_section.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';
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
    final theme = adminThemeDataFor(ref.watch(adminThemeProvider));
    final palette = theme.extension<AdminPalette>() ?? AdminPalette.light;

    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => PortalShell(
          selectedItemColor: AdminTheme.sealGold,
          // A light bar over the navy page band, not a second navy one.
          // AdminPageHeader exists precisely because stacking two navy bars
          // looked broken, and its title, subtitle and eyebrow are all pinned
          // to a dark background -- so the band keeps admin's identity and the
          // bar stays the quiet chrome, exactly as the public site's paper bar
          // sits above its tinted page band.
          background: palette.card,
          foreground: palette.ink,
          borderColor: palette.border,
          activeColor: AdminTheme.harborBlue,
          // Gold marks "you are here" on every surface in the product.
          underlineColor: AdminTheme.sealGold,
          // The admin build has no router and no public site to return to,
          // so the brand mark is deliberately inert here.
          onBrandTap: () {},
          actionsWidth: _actionsWidth,
          actionsBuilder: (context, layout) => [
            if (!layout.compact) const SizedBox(width: 12),
            // The portal's own light/dark switch. It doesn't follow the
            // browser on purpose -- see providers/admin_theme_provider.dart.
            Consumer(
              builder: (context, ref, _) {
                final isDark = ref.watch(adminThemeProvider) == AdminThemeMode.dark;
                return IconButton(
                  tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
                  icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  onPressed: () => ref.read(adminThemeProvider.notifier).toggle(),
                );
              },
            ),
            const NotificationBell(),
            // An account menu rather than a bare sign-out button, so admins
            // can also change their password.
            PopupMenuButton<String>(
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
            ),
          ],
          // Admin screens are lists, maps and charts rather than the
          // phone-shaped forms the owner portal is built from, so they get a
          // wider measure than the site's 1100 prose column.
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
      ),
    );
  }

  /// Three 44px icon buttons plus the gap before them, measured on the same
  /// basis the website measures its own cluster.
  static const double _actionsWidth = 12 + 44 + 44 + 44;
}
