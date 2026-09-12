import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_palette.dart';

/// Design tokens for the WASA Admin portal (lib/screens/admin/, both the
/// mobile-app admin login and the standalone admin portal website --
/// AdminNavigation is the same widget tree either way).
///
/// Deliberately shares its actual palette values with the public website
/// (constants/web_theme.dart's ink navy / harbor blue / gold seal), not a
/// coincidence: WASA's whole identity is about certifying which stations
/// are trustworthy, and admin is the team that actually does that
/// certifying -- a more literal fit for the "seal" language than the
/// marketing site itself.
///
/// Tuned larger/higher-contrast than the mobile app's default theme --
/// mirrors the precedent already set by the driver palette: admin's users
/// skew older, so this scales text and touch targets up rather than using
/// Material's compact defaults.
///
/// **Light and dark.** The portal is pinned to its own theme (AdminNavigation
/// and adminRoute both wrap in it) so it can never inherit the public site's
/// theme and render white cards on a dark page. The mode itself comes from
/// the admin's own switch in the header (providers/admin_theme_provider.dart),
/// not the browser: an association officer opening the portal on a PC that
/// happens to be set to dark shouldn't have the tool change appearance
/// without asking.
class AdminTheme {
  AdminTheme._();

  // -- Brand accents: identical in both modes. --------------------------
  static const inkNavy = Color(0xFF0B2545);
  static const harborBlue = Color(0xFF1565C0);
  static const sealGold = Color(0xFFC99A3B);
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
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? AdminPalette.dark : AdminPalette.light;

    // Lightened on dark so the brand blue stays legible on navy; light mode
    // keeps the exact blue the portal already used.
    final primary = isDark ? const Color(0xFF6FB1F0) : harborBlue;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: harborBlue,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF04243F) : Colors.white,
      secondary: sealGold,
      onSecondary: isDark ? Colors.black : inkNavy,
      surface: palette.card,
      onSurface: palette.ink,
      onSurfaceVariant: palette.inkMuted,
      outline: palette.border,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      useMaterial3: true,
      visualDensity: VisualDensity.comfortable,
      scaffoldBackgroundColor: palette.paper,
    );

    // ThemeData's textTheme carries colors but NOT sizes: every fontSize is
    // still null at construction time, because ThemeData.localize merges the
    // script geometry in later, during the widget build. Calling
    // .apply(fontSizeFactor:) on it therefore asserts in debug and, with
    // asserts stripped in release, silently no-ops (`fontSize == null ? null
    // : fontSize * factor`) -- which quietly cost admin the larger type this
    // theme exists to provide. Merge the geometry in first so every style has
    // a real size to scale, exactly as localize would have.
    final sized = Typography.material2021(
      platform: base.platform,
      colorScheme: colorScheme,
    ).englishLike.merge(base.textTheme);

    return base.copyWith(
      extensions: [palette],
      textTheme: sized
          .apply(fontSizeFactor: 1.12, bodyColor: palette.ink, displayColor: palette.ink)
          .copyWith(
            titleLarge: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: palette.ink),
            titleMedium: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, color: palette.ink),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: headerBand,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white, size: 26),
        // Under edge-to-edge the status bar sits over this band, and the band
        // is navy in *both* modes -- so its icons are always light, unlike
        // AppTheme's, which follow the surface. The navigation bar is over the
        // scaffold instead, so that one does follow the palette.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        // Same gold rule AdminPageHeader draws, so a pushed screen's real
        // AppBar (which keeps its back button) and a tab page's in-body
        // header terminate identically.
        shape: const Border(bottom: BorderSide(color: sealGold, width: 3)),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isDark ? BorderSide(color: palette.border) : BorderSide.none,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        titleTextStyle: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: palette.ink),
        subtitleTextStyle: TextStyle(fontSize: 14, color: palette.inkMuted),
        minVerticalPadding: 14,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),
      iconTheme: IconThemeData(color: primary, size: 26),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? sealGold : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? sealGold.withValues(alpha: 0.5) : null,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.card,
        selectedIconTheme: IconThemeData(color: primary, size: 28),
        selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 13),
        unselectedIconTheme: IconThemeData(color: palette.inkMuted, size: 26),
        unselectedLabelTextStyle: TextStyle(color: palette.inkMuted, fontSize: 13),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.card,
        selectedItemColor: primary,
        unselectedItemColor: palette.inkMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(color: palette.border),
      dialogTheme: DialogThemeData(backgroundColor: palette.card),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.foam,
        labelStyle: TextStyle(color: palette.ink),
        side: BorderSide(color: palette.border),
      ),
    );
  }
}
