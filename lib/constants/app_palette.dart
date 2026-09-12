import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Surfaces and text for the app's customer and station-owner screens, in
/// both modes. Mirrors WebPalette (constants/web_theme.dart) deliberately:
/// the brand accents stay constant in [AppColors] because they read on
/// either background, and only the values that must invert live here.
///
/// Read with `AppPalette.of(context)`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.paper,
    required this.foam,
    required this.card,
    required this.ink,
    required this.inkMuted,
    required this.border,
    required this.isDark,
  });

  /// Page background.
  final Color paper;

  /// Tinted background for callouts and alternating blocks.
  final Color foam;

  /// Card and raised-surface fill.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text -- captions, metadata, helper lines.
  final Color inkMuted;

  final Color border;
  final bool isDark;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette.light;

  static const light = AppPalette(
    paper: AppColors.surface,
    foam: AppColors.surfaceAlt,
    card: AppColors.card,
    ink: AppColors.ink,
    inkMuted: AppColors.inkMuted,
    border: AppColors.border,
    isDark: false,
  );

  /// The same navy the brand already uses, carried down into the
  /// backgrounds, and off-white text rather than pure white so a phone at
  /// full brightness in a dark room isn't glaring. Matches the website's
  /// dark palette so the two products still look like one.
  static const dark = AppPalette(
    paper: Color(0xFF0A1826),
    foam: Color(0xFF102434),
    card: Color(0xFF15293B),
    ink: Color(0xFFEDF2F7),
    inkMuted: Color(0xFF9AAABC),
    border: Color(0xFF23384C),
    isDark: true,
  );

  @override
  AppPalette copyWith({
    Color? paper,
    Color? foam,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? border,
    bool? isDark,
  }) {
    return AppPalette(
      paper: paper ?? this.paper,
      foam: foam ?? this.foam,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      border: border ?? this.border,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      foam: Color.lerp(foam, other.foam, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// The driver portal's own palette. It is deliberately high-contrast for
/// reading at arm's length in a vehicle, in daylight or at night -- the
/// dark values are the ones the portal has always used; the light ones keep
/// the same separation on a bright screen.
///
/// Read with `DriverPalette.of(context)`.
@immutable
class DriverPalette extends ThemeExtension<DriverPalette> {
  const DriverPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.textMuted,
    required this.onDuty,
    required this.offDuty,
    required this.alert,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color text;

  /// Labels and secondary lines. The portal used Colors.grey.shade700 for
  /// this on a near-black background, which was barely legible.
  final Color textMuted;

  final Color onDuty;
  final Color offDuty;
  final Color alert;
  final bool isDark;

  static DriverPalette of(BuildContext context) =>
      Theme.of(context).extension<DriverPalette>() ?? DriverPalette.dark;

  static const dark = DriverPalette(
    background: AppColors.driverBackground,
    surface: AppColors.driverSurface,
    text: AppColors.driverText,
    textMuted: Color(0xFFB5C0CC),
    onDuty: AppColors.driverOnDuty,
    offDuty: AppColors.driverOffDuty,
    alert: AppColors.driverAlert,
    isDark: true,
  );

  /// Greens and reds are darkened for a white background -- the dark mode's
  /// bright #00C853 on white fails contrast badly.
  static const light = DriverPalette(
    background: Color(0xFFF4F6F8),
    surface: Colors.white,
    text: AppColors.ink,
    textMuted: AppColors.inkMuted,
    onDuty: Color(0xFF1B7F3B),
    offDuty: Color(0xFF5A6675),
    alert: Color(0xFFC62828),
    isDark: false,
  );

  @override
  DriverPalette copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? textMuted,
    Color? onDuty,
    Color? offDuty,
    Color? alert,
    bool? isDark,
  }) {
    return DriverPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      onDuty: onDuty ?? this.onDuty,
      offDuty: offDuty ?? this.offDuty,
      alert: alert ?? this.alert,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  DriverPalette lerp(ThemeExtension<DriverPalette>? other, double t) {
    if (other is! DriverPalette) return this;
    return DriverPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      onDuty: Color.lerp(onDuty, other.onDuty, t)!,
      offDuty: Color.lerp(offDuty, other.offDuty, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
