import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the WASA Admin portal (lib/screens/admin/, both the
/// mobile-app admin login and the standalone admin portal website --
/// AdminNavigation is the same widget tree either way).
///
/// Deliberately shares its actual palette values with the public website
/// (constants/web_theme.dart's ink navy / harbor blue / gold seal), not a
/// coincidence: WASA's whole identity is about certifying which stations
/// are trustworthy, and admin is the team that actually does that
/// certifying -- a more literal fit for the "seal" language than the
/// marketing site itself. Now that admin has its own portal site
/// (deploy_admin_web.ps1), sharing this identity is a real uniformity
/// story, not a cosmetic one.
///
/// Tuned larger/higher-contrast than the mobile app's default theme --
/// mirrors the precedent already set by AppColors.driver* (its own tuned
/// palette for daylight-road readability): admin's users skew older, so
/// this scales text and touch targets up rather than using Material's
/// compact defaults.
class AdminTheme {
  AdminTheme._();

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

  /// Axis labels, gridlines and other chart furniture -- deliberately low
  /// contrast so the data, not the scaffolding, is what reads first.
  static Color chartAxis = inkNavy.withValues(alpha: 0.55);
  static Color chartGrid = inkNavy.withValues(alpha: 0.08);

  static ThemeData get themeData {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: harborBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: harborBlue,
      onPrimary: Colors.white,
      secondary: sealGold,
      onSecondary: inkNavy,
      surface: Colors.white,
      onSurface: inkNavy,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: VisualDensity.comfortable,
      scaffoldBackgroundColor: foam,
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
      textTheme: sized
          .apply(fontSizeFactor: 1.12, bodyColor: inkNavy, displayColor: inkNavy)
          .copyWith(
            titleLarge: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: inkNavy),
            titleMedium: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, color: inkNavy),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: inkNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white, size: 26),
        // Same gold rule AdminPageHeader draws, so a pushed screen's real
        // AppBar (which keeps its back button) and a tab page's in-body
        // header terminate identically.
        shape: const Border(bottom: BorderSide(color: sealGold, width: 3)),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: harborBlue,
        titleTextStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: inkNavy),
        subtitleTextStyle: TextStyle(fontSize: 14, color: inkNavy.withValues(alpha: 0.65)),
        minVerticalPadding: 14,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: harborBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: harborBlue,
          side: const BorderSide(color: harborBlue, width: 1.5),
          minimumSize: const Size(64, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: harborBlue,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
      ),
      iconTheme: const IconThemeData(color: harborBlue, size: 26),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? sealGold : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? sealGold.withValues(alpha: 0.5) : null,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: const IconThemeData(color: harborBlue, size: 28),
        selectedLabelTextStyle: const TextStyle(color: harborBlue, fontWeight: FontWeight.w700, fontSize: 13),
        unselectedIconTheme: IconThemeData(color: inkNavy.withValues(alpha: 0.5), size: 26),
        unselectedLabelTextStyle: TextStyle(color: inkNavy.withValues(alpha: 0.5), fontSize: 13),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: harborBlue,
        unselectedItemColor: inkNavy.withValues(alpha: 0.4),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      dividerTheme: DividerThemeData(color: inkNavy.withValues(alpha: 0.12)),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: foam,
        labelStyle: const TextStyle(color: inkNavy),
      ),
    );
  }
}
