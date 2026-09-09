import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/admin_theme.dart';

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
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.showSignOut = true,
  });

  final String title;
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
                          if (showSignOut && !canPop)
                            IconButton(
                              icon: const Icon(Icons.logout),
                              tooltip: 'Sign Out',
                              onPressed: () => Supabase.instance.client.auth.signOut(),
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
