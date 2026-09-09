import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Theme for the in-app portals: merchant (station owner) and customer.
///
/// Mirrors the structure of admin_theme.dart and web_theme.dart so the
/// product has one identity across all three surfaces instead of three. The
/// palette and the Fraunces display face are the ones the website and admin
/// portal already use; nothing new is invented here.
///
/// **Light only, and deliberately so.** main.dart hands WebTheme.light /
/// WebTheme.dark to every surface, driven by the website's dark-mode toggle.
/// These screens were written assuming a light background -- toggling dark on
/// the public site and then signing in as a station owner rendered the
/// merchant portal on a dark page with white cards and grey-on-dark text, and
/// the merchant portal has no toggle to get back out. Pinning here removes
/// that class of bug by construction rather than by remembering to check two
/// modes on every screen.
///
/// Applied by wrapping the shells (MerchantNavigation, PublicHomeScreen) in
/// `Theme(data: AppTheme.light, ...)`. Screens opened with Navigator.push do
/// NOT inherit it -- use `appRoute()` (screens/app_route.dart) for those.
class AppTheme {
  AppTheme._();

  /// One radius for the whole app. The codebase had eleven different values
  /// in use (1, 3, 4, 6, 8, 10, 12, 14, 16, 20, 999), which is what a missing
  /// scale looks like rather than a design decision.
  static const double radius = 12;
  static const double radiusSmall = 8;

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.seal,
      onSecondary: AppColors.ink,
      surface: AppColors.card,
      onSurface: AppColors.ink,
      error: AppColors.flagged,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        titleTextStyle: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.ink),
        subtitleTextStyle: TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surfaceAlt,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.inkMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700),
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
    );
  }

  /// Explicit sizes on every style.
  ///
  /// Deliberately NOT `base.textTheme.apply(fontSizeFactor: ...)`: ThemeData's
  /// text theme carries colours but not sizes at construction time (the script
  /// geometry is merged in later by ThemeData.localize), so `.apply` with a
  /// factor asserts in debug and silently no-ops in release. AdminTheme hit
  /// exactly that and lost the larger type it was supposed to provide.
  static TextTheme _textTheme(TextTheme base) {
    TextStyle display(double size, {FontWeight weight = FontWeight.w600}) =>
        GoogleFonts.fraunces(fontSize: size, fontWeight: weight, color: AppColors.ink, height: 1.2);

    TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color ?? AppColors.ink, height: 1.4);

    // Fraunces for headings only -- the same restraint the website uses, so
    // the display face stays a signal rather than decoration.
    return base.copyWith(
      headlineLarge: display(30),
      headlineMedium: display(26),
      headlineSmall: display(22),
      titleLarge: display(20),
      titleMedium: body(16, weight: FontWeight.w700),
      titleSmall: body(14, weight: FontWeight.w700),
      bodyLarge: body(16),
      bodyMedium: body(14.5),
      bodySmall: body(13, color: AppColors.inkMuted),
      labelLarge: body(14.5, weight: FontWeight.w600),
      labelMedium: body(13, weight: FontWeight.w600, color: AppColors.inkMuted),
      labelSmall: body(12, weight: FontWeight.w600, color: AppColors.inkMuted),
    );
  }
}
