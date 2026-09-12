import 'package:flutter/material.dart';

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

  static const light = AdminPalette(
    paper: Color(0xFFEAF3F5),
    foam: Color(0xFFEAF3F5),
    card: Colors.white,
    ink: Color(0xFF0B2545),
    inkMuted: Color(0xFF4C6376),
    border: Color(0xFFD5DFE6),
    isDark: false,
  );

  /// Navy carried down into the backgrounds rather than a pure-black dark
  /// mode, so the portal still reads as the same product, with off-white
  /// text to stay comfortable on a large monitor.
  static const dark = AdminPalette(
    paper: Color(0xFF0C1A2A),
    foam: Color(0xFF13273A),
    card: Color(0xFF16293C),
    ink: Color(0xFFEDF2F4),
    inkMuted: Color(0xFF9FB2C2),
    border: Color(0xFF26394C),
    isDark: true,
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
