import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// Theme for the in-app portals: merchant (station owner), customer and
/// driver.
///
/// Mirrors the structure of admin_theme.dart and web_theme.dart so the
/// product has one identity across all three surfaces instead of three. The
/// palette and the Fraunces display face are the ones the website and admin
/// portal already use; nothing new is invented here.
///
/// **Both modes, chosen by the phone.** These screens were written for a
/// light background and were pinned to [light] while that was the only mode
/// that existed -- otherwise a visitor who switched the public site to dark
/// and then signed in as a station owner got white cards on a dark page.
/// Now the mode comes from the phone (providers/app_theme_provider.dart,
/// with a Light/Dark/Follow-phone override in Account settings) and every
/// surface colour comes from [AppPalette], so both modes are designed
/// rather than one being an accident.
///
/// Applied by wrapping the shells (MerchantNavigation, PublicHomeScreen) and
/// by `appRoute()` (screens/app_route.dart) for pushed screens, which do not
/// inherit a local Theme.
class AppTheme {
  AppTheme._();

  /// One radius for the whole app. The codebase had eleven different values
  /// in use (1, 3, 4, 6, 8, 10, 12, 14, 16, 20, 999), which is what a missing
  /// scale looks like rather than a design decision.
  static const double radius = 12;
  static const double radiusSmall = 8;

  static ThemeData get light => themeFor(Brightness.light);
  static ThemeData get dark => themeFor(Brightness.dark);

  static ThemeData themeFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final driverPalette = isDark ? DriverPalette.dark : DriverPalette.light;

    // Lightened on dark so the brand blue stays legible on a navy surface;
    // the light mode keeps the exact blue the product already uses.
    final primary = isDark ? const Color(0xFF6FB1F0) : AppColors.primary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF04243F) : Colors.white,
      secondary: AppColors.seal,
      onSecondary: isDark ? Colors.black : AppColors.ink,
      surface: palette.card,
      onSurface: palette.ink,
      onSurfaceVariant: palette.inkMuted,
      outline: palette.border,
      error: isDark ? const Color(0xFFFF8A80) : AppColors.flagged,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: palette.paper,
    );

    return base.copyWith(
      extensions: [palette, driverPalette],
      textTheme: _textTheme(base.textTheme, palette),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.paper,
        foregroundColor: palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: palette.ink,
        ),
        iconTheme: IconThemeData(color: palette.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: palette.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        titleTextStyle: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: palette.ink),
        subtitleTextStyle: TextStyle(fontSize: 13.5, color: palette.inkMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.foam,
        side: BorderSide(color: palette.border),
        labelStyle: TextStyle(color: palette.ink, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: palette.border, space: 1, thickness: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.card,
        selectedItemColor: primary,
        unselectedItemColor: palette.inkMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? palette.foam : AppColors.ink,
        contentTextStyle: TextStyle(color: isDark ? palette.ink : Colors.white),
        actionTextColor: isDark ? primary : AppColors.seal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      dialogTheme: DialogThemeData(backgroundColor: palette.card),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: palette.card),
    );
  }

  /// Explicit sizes on every style.
  ///
  /// Deliberately NOT `base.textTheme.apply(fontSizeFactor: ...)`: ThemeData's
  /// text theme carries colours but not sizes at construction time (the script
  /// geometry is merged in later by ThemeData.localize), so `.apply` with a
  /// factor asserts in debug and silently no-ops in release. AdminTheme hit
  /// exactly that and lost the larger type it was supposed to provide.
  static TextTheme _textTheme(TextTheme base, AppPalette palette) {
    TextStyle display(double size, {FontWeight weight = FontWeight.w600}) =>
        GoogleFonts.fraunces(fontSize: size, fontWeight: weight, color: palette.ink, height: 1.2);

    TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color ?? palette.ink, height: 1.4);

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
      bodySmall: body(13, color: palette.inkMuted),
      labelLarge: body(14.5, weight: FontWeight.w600),
      labelMedium: body(13, weight: FontWeight.w600, color: palette.inkMuted),
      labelSmall: body(12, weight: FontWeight.w600, color: palette.inkMuted),
    );
  }
}
