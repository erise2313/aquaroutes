import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_theme_provider.dart';

/// Light/dark switch for the app's own portals, for the app bars of the
/// customer and station-owner screens.
///
/// Account settings has the full three-way choice (Light / Dark / Follow
/// phone). This exists because the control people actually used -- the
/// public website's toggle in the nav bar -- disappears the moment they sign
/// in, leaving a station owner in a dark portal with no visible way back.
///
/// Tapping moves between light and dark explicitly; "Follow phone" stays
/// available in Account settings for anyone who wants it back.
class AppThemeToggle extends ConsumerWidget {
  const AppThemeToggle({super.key, this.color});

  /// For app bars that paint their own foreground colour.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appThemeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: color),
      onPressed: () => ref.read(appThemeProvider.notifier).set(
            isDark ? AppThemeMode.light : AppThemeMode.dark,
          ),
    );
  }
}
