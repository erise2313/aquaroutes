import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'brand_fonts.dart';

import 'brand_tokens.dart';

/// Builds the ThemeData that AppTheme, WebTheme and AdminTheme all share.
///
/// Each of those keeps its own class and palette extension (so no screen has
/// to change what it reads), but the component styling -- cards, buttons,
/// inputs, bars, chips, dialogs -- is defined once, here, from the app's
/// design. That single definition is what makes the admin portal and the
/// website look like the app.
class BrandTheme {
  BrandTheme._();

  static ThemeData build(
    Brightness brightness, {
    required List<ThemeExtension<dynamic>> extensions,
  }) {
    final isDark = brightness == Brightness.dark;
    final s = BrandSurfaces.of(brightness);
    final primary = isDark ? BrandColors.harborBlueOnDark : BrandColors.harborBlue;
    final onPrimary = isDark ? BrandColors.onHarborBlueOnDark : Colors.white;
    final danger = BrandStatus.dangerFor(brightness);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: BrandColors.harborBlue,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: BrandColors.sealGold,
      onSecondary: isDark ? Colors.black : BrandColors.inkNavy,
      surface: s.card,
      onSurface: s.ink,
      onSurfaceVariant: s.inkMuted,
      surfaceContainerHighest: s.foam,
      outline: s.inputBorder,
      outlineVariant: s.border,
      error: danger,
    );

    final base = ThemeData(
      colorScheme: colorScheme,
      brightness: brightness,
      useMaterial3: true,
      fontFamily: BrandFonts.family,
      scaffoldBackgroundColor: s.paper,
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrandRadius.control));
    const buttonText = TextStyle(fontFamily: BrandFonts.family, fontSize: BrandType.labelLarge, fontWeight: FontWeight.w700);
    const minButton = Size(64, BrandType.minTarget);
    // The one main action on a screen is a filled button; it gets the
    // larger target the UI plan asks for (56), the rest keep 48.
    const minPrimaryButton = Size(64, BrandType.minPrimaryTarget);

    return base.copyWith(
      extensions: extensions,
      textTheme: textTheme(s),
      iconTheme: IconThemeData(color: s.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: s.paper,
        foregroundColor: s.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Set here rather than through SystemChrome at startup: AppBar applies
        // its own overlay style on every build, so a global call is silently
        // overridden on any screen that has one.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
        titleTextStyle: BrandFonts.display(fontSize: BrandType.titleLarge, fontWeight: FontWeight.w600, color: s.ink),
        iconTheme: IconThemeData(color: s.ink),
        shape: Border(bottom: BorderSide(color: s.border)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: s.card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandRadius.card),
          side: BorderSide(color: s.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        titleTextStyle: TextStyle(fontSize: BrandType.titleSmall + 1, fontWeight: FontWeight.w600, color: s.ink),
        subtitleTextStyle: TextStyle(fontSize: BrandType.bodySmall, color: s.inkMuted),
        minVerticalPadding: 10,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: minPrimaryButton,
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: minPrimaryButton,
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          minimumSize: minButton,
          textStyle: buttonText,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, BrandType.minTarget),
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(BrandType.minTarget, BrandType.minTarget)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.card,
        // In a multi-line box the label sits at the top, not floating in
        // the middle of the empty space.
        alignLabelWithHint: true,
        labelStyle: TextStyle(color: s.inkMuted, fontSize: BrandType.bodyMedium),
        floatingLabelStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: s.inkMuted),
        helperStyle: TextStyle(color: s.inkMuted, fontSize: BrandType.labelSmall),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: s.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: s.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrandRadius.control),
          borderSide: BorderSide(color: danger),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: s.foam,
        selectedColor: primary.withValues(alpha: isDark ? 0.28 : 0.14),
        side: BorderSide(color: s.border),
        labelStyle: TextStyle(color: s.ink, fontWeight: FontWeight.w600, fontSize: BrandType.labelMedium),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrandRadius.control)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: s.inputBorder, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: s.card,
          foregroundColor: s.ink,
          selectedBackgroundColor: primary.withValues(alpha: isDark ? 0.3 : 0.12),
          selectedForegroundColor: primary,
          side: BorderSide(color: s.inputBorder),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: BrandType.labelLarge),
          minimumSize: const Size(0, BrandType.minTarget),
          shape: controlShape,
        ),
      ),
      dividerTheme: DividerThemeData(color: s.border, space: 1, thickness: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: s.inkMuted,
        indicatorColor: primary,
        labelStyle: const TextStyle(fontSize: BrandType.labelLarge, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: BrandType.labelLarge, fontWeight: FontWeight.w500),
        dividerColor: s.border,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: s.card,
        selectedIconTheme: IconThemeData(color: primary),
        selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: BrandType.labelSmall),
        unselectedIconTheme: IconThemeData(color: s.inkMuted),
        unselectedLabelTextStyle: TextStyle(color: s.inkMuted, fontSize: BrandType.labelSmall),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: s.card,
        selectedItemColor: primary,
        unselectedItemColor: s.inkMuted,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: BrandType.labelSmall),
        unselectedLabelStyle: const TextStyle(fontSize: BrandType.labelSmall),
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? s.foam : BrandColors.inkNavy,
        contentTextStyle: TextStyle(color: isDark ? s.ink : Colors.white, fontSize: BrandType.bodyMedium),
        actionTextColor: isDark ? primary : BrandColors.sealGold,
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(fontSize: BrandType.labelMedium, color: Colors.white),
        decoration: BoxDecoration(color: BrandColors.inkNavy, borderRadius: BorderRadius.circular(6)),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: BrandFonts.display(fontSize: BrandType.titleLarge, fontWeight: FontWeight.w600, color: s.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BrandRadius.card)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: s.card, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: s.card, surfaceTintColor: Colors.transparent),
      drawerTheme: DrawerThemeData(backgroundColor: s.card, surfaceTintColor: Colors.transparent),
    );
  }

  /// Explicit sizes on every style.
  ///
  /// Deliberately NOT `base.textTheme.apply(fontSizeFactor: ...)`: ThemeData's
  /// text theme carries colours but not sizes at construction time (the script
  /// geometry is merged in later by ThemeData.localize), so `.apply` with a
  /// factor asserts in debug and silently no-ops in release.
  static TextTheme textTheme(BrandSurfaces s) {
    TextStyle display(double size) =>
        BrandFonts.display(fontSize: size, fontWeight: FontWeight.w700, color: s.ink, height: 1.3);

    // Regular or Bold only: Atkinson has no in-between weights.
    TextStyle body(double size, {bool bold = false, Color? color}) => TextStyle(
          fontFamily: BrandFonts.family,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: color ?? s.ink,
          height: 1.5,
        );

    return TextTheme(
      displayLarge: display(48),
      displayMedium: display(40),
      displaySmall: display(36),
      headlineLarge: display(BrandType.headlineLarge),
      headlineMedium: display(BrandType.headlineMedium),
      headlineSmall: display(BrandType.headlineSmall),
      titleLarge: display(BrandType.titleLarge),
      titleMedium: body(BrandType.titleMedium, bold: true),
      titleSmall: body(BrandType.titleSmall, bold: true),
      bodyLarge: body(BrandType.bodyLarge),
      bodyMedium: body(BrandType.bodyMedium),
      bodySmall: body(BrandType.bodySmall, color: s.inkMuted),
      labelLarge: body(BrandType.labelLarge, bold: true),
      labelMedium: body(BrandType.labelMedium, bold: true, color: s.inkMuted),
      labelSmall: body(BrandType.labelSmall, bold: true, color: s.inkMuted),
    );
  }
}
