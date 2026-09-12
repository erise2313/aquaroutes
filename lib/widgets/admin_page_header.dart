import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/admin_theme.dart';
import '../providers/admin_theme_provider.dart';
import 'account_settings_section.dart';
import 'notification_bell.dart';

/// The single header on an admin page -- an in-body header rather than an
/// AppBar, so admin pages render exactly one navy bar instead of the two
/// that stacking a page AppBar under the nav shell's AppBar produced.
///
/// Adapts to how the page was reached: a tab page (nothing to pop) gets
/// sign-out on the right, while a pushed page (e.g. Worker Clearance opened
/// from the Dashboard's review queue) gets a back button instead -- without
/// it a pushed page using this header would have no visible way back, since
/// it has no AppBar to supply one.
///
/// The gold underline echoes the public website's active-nav-tab treatment
/// (widgets/web_nav_bar.dart) -- same "you are here / this matters" motif,
/// carried onto admin, and matched by AdminTheme's appBarTheme shape so
/// pushed screens that do keep a real AppBar terminate identically.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.showSignOut = true,
  });

  final String title;

  /// Small caps above the title -- which part of the portal this page
  /// belongs to. The same rhythm the public site and the owner portal use
  /// (widgets/portal/portal_page_header.dart), in admin's own gold.
  final String? eyebrow;

  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;

  /// Sign-out lives here rather than in a separate top bar -- it's the same
  /// action on every admin screen, and giving it its own AppBar meant two
  /// stacked navy bars on every page. Automatically suppressed on a pushed
  /// page, which shows a back button instead.
  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: AdminTheme.inkNavy,
        border: Border(bottom: BorderSide(color: AdminTheme.sealGold, width: 3)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 20, bottom == null ? 20 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (canPop)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!.toUpperCase(),
                            style: const TextStyle(
                              color: AdminTheme.sealGold,
                              fontSize: 11,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(title, style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                  // Actions sit on the dark header, not the light body --
                  // force white icon/text regardless of the admin theme's
                  // default (harbor-blue) button colors, which would be
                  // low-contrast here.
                  IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: TextButtonTheme(
                      data: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Colors.white)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...actions,
                          // The portal's own light/dark switch. It doesn't
                          // follow the browser on purpose -- see
                          // providers/admin_theme_provider.dart.
                          if (showSignOut && !canPop)
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
                          if (showSignOut && !canPop) const NotificationBell(),
                          // An account menu rather than a bare sign-out button,
                          // so admins can also change their password.
                          if (showSignOut && !canPop)
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
                      ),
                    ),
                  ),
                ],
              ),
              if (bottom != null) ...[const SizedBox(height: 16), bottom!],
            ],
          ),
        ),
      ),
    );
  }
}
