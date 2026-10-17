import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// Surfaces and text for the WASA Admin portal, in both modes.
///
/// Same split as [WebPalette] and [AppPalette]: the brand accents in
/// [AdminTheme] (ink navy, harbor blue, seal gold) are constants because
/// they carry the identity and read on either background, while everything
/// that has to invert lives here.
///
/// Read with `AdminPalette.of(context)`.
@immutable
class AdminPalette extends ThemeExtension<AdminPalette> {
  const AdminPalette({
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

  /// The rail, filter bar and other alternating blocks.
  final Color foam;

  /// Card and raised-surface fill.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text -- captions, metadata, empty-state copy.
  final Color inkMuted;

  final Color border;
  final bool isDark;

  /// Axis labels and gridlines: deliberately low contrast so the data, not
  /// the scaffolding, is what reads first.
  Color get chartAxis => ink.withValues(alpha: 0.55);
  Color get chartGrid => ink.withValues(alpha: 0.12);

  static AdminPalette of(BuildContext context) =>
      Theme.of(context).extension<AdminPalette>() ?? AdminPalette.light;

  /// The same surfaces as the app and the website. Admin used to sit on a
  /// blue-grey page of its own, which is a large part of why it read as a
  /// different product during the evaluation.
  static final light = AdminPalette.fromSurfaces(BrandSurfaces.light, isDark: false);
  static final dark = AdminPalette.fromSurfaces(BrandSurfaces.dark, isDark: true);

  factory AdminPalette.fromSurfaces(BrandSurfaces s, {required bool isDark}) => AdminPalette(
        paper: s.paper,
        foam: s.foam,
        card: s.card,
        ink: s.ink,
        inkMuted: s.inkMuted,
        border: s.border,
        isDark: isDark,
      );

  @override
  AdminPalette copyWith({
    Color? paper,
    Color? foam,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? border,
    bool? isDark,
  }) {
    return AdminPalette(
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
  AdminPalette lerp(ThemeExtension<AdminPalette>? other, double t) {
    if (other is! AdminPalette) return this;
    return AdminPalette(
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
