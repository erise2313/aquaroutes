import 'package:flutter/material.dart';

import 'admin_palette.dart';
import 'brand_theme.dart';
import 'brand_tokens.dart';

/// Theme for the WASA Admin portal (lib/screens/admin/, both the mobile-app
/// admin login and the standalone admin portal website -- AdminNavigation is
/// the same widget tree either way).
///
/// Component styling comes from [BrandTheme], shared with the app and the
/// website: during the evaluation the portal's own look (blue-grey page,
/// shadowed cards, a navy band on every page) made it read as a different
/// product from the app people found easy. The portal keeps only its palette
/// extension and the chart colours.
///
/// **Light and dark.** The portal is pinned to its own theme (AdminNavigation
/// and adminRoute both wrap in it) so it can never inherit the public site's
/// theme. The mode comes from the admin's own switch
/// (providers/admin_theme_provider.dart), not the browser: an officer opening
/// the portal on a PC that happens to be set to dark shouldn't have the tool
/// change appearance without asking.
class AdminTheme {
  AdminTheme._();

  // -- Brand accents: identical in both modes. --------------------------
  static const inkNavy = BrandColors.inkNavy;
  static const harborBlue = BrandColors.harborBlue;
  static const sealGold = BrandColors.sealGold;
  static const foam = Color(0xFFEAF3F5);

  /// Ordered series colours for dashboard charts. Drawn from the portal's own
  /// palette so a chart reads as part of the page rather than a widget
  /// dropped in from a library, and ordered so the first (and often only)
  /// series is the brand blue.
  static const chartSeries = <Color>[
    harborBlue,
    sealGold,
    Color(0xFF2E7D32), // matches AppColors.cleared
    Color(0xFF0B4F5C), // deep teal, shared with the public site
    Color(0xFF8E6BAF),
  ];

  /// Kept for any call site still reading the old constants; the mode-aware
  /// values live on [AdminPalette] (`AdminPalette.of(context).chartAxis`).
  static Color chartAxis = inkNavy.withValues(alpha: 0.55);
  static Color chartGrid = inkNavy.withValues(alpha: 0.08);

  /// The header band stays navy in both modes -- it's the portal's
  /// identity, and white-on-navy is legible either way.
  static const headerBand = inkNavy;

  static ThemeData get light => themeFor(Brightness.light);
  static ThemeData get dark => themeFor(Brightness.dark);

  /// Existing call sites that predate dark mode.
  static ThemeData get themeData => light;

  static ThemeData themeFor(Brightness brightness) {
    final palette = brightness == Brightness.dark ? AdminPalette.dark : AdminPalette.light;
    return BrandTheme.build(brightness, extensions: [palette]);
  }
}
