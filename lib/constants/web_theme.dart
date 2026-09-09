import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the public website only (lib/screens/web/, web_nav_bar,
/// web_footer). Deliberately separate from constants/app_colors.dart so the
/// mobile app's screens are untouched by this pass.
///
/// Grounding: WASA's actual job is certifying which water stations are
/// trustworthy -- accreditation IS the product. The palette and the
/// recurring gold "seal" motif (see WebSeal in wave_divider.dart's sibling
/// widgets) lean into that directly, instead of a generic water/blue theme.
///
/// Split into two groups on purpose:
///
///  * **Brand accents** (harbor blue, seal gold, deep teal) are plain
///    constants. They carry the identity and read correctly on either
///    background, so they must NOT change between light and dark -- and
///    keeping them const means WebSeal stays usable inside the admin portal,
///    which has its own theme and never registers [WebPalette].
///  * **Surfaces and text** live in [WebPalette], a ThemeExtension, because
///    those are exactly the values that have to invert. Read them with
///    `WebTheme.of(context)`.
class WebTheme {
  WebTheme._();

  // -- Brand accents: identical in both modes. --------------------------
  static const inkNavy = Color(0xFF0B2545);
  static const harborBlue = Color(0xFF1565C0);
  static const sealGold = Color(0xFFC99A3B);
  static const deepTeal = Color(0xFF0B4F5C);

  /// Legacy light-mode surface constants. Still referenced by the mobile
  /// app's info screens, which are not part of the website's theming and
  /// stay light. Website code should use `WebTheme.of(context)` instead.
  static const paper = Color(0xFFF7F5F0);
  static const foam = Color(0xFFEAF3F5);

  /// Surfaces and text for the current mode.
  static WebPalette of(BuildContext context) =>
      Theme.of(context).extension<WebPalette>() ?? WebPalette.light;

  /// Fraunces for display/heading type -- the one deliberate typographic
  /// choice; body text stays the default system sans everywhere else.
  ///
  /// [color] defaults to null so the text inherits whatever the active
  /// theme's text colour is. That is what lets every heading on the site
  /// flip with the mode without touching a single call site; pass a colour
  /// only where the background is fixed regardless of mode (e.g. the hero).
  static TextStyle display({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.fraunces(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
  }

  static TextStyle heroDisplay({Color color = Colors.white}) {
    return GoogleFonts.fraunces(fontSize: 48, fontWeight: FontWeight.w600, color: color, height: 1.1);
  }

  /// Gold on either background, so it needs no mode variant.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    color: sealGold,
  );

  static ThemeData themeFor(Brightness brightness) {
    final palette = brightness == Brightness.dark ? WebPalette.dark : WebPalette.light;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: harborBlue,
        brightness: brightness,
      ).copyWith(
        primary: brightness == Brightness.dark ? const Color(0xFF6FB1F0) : harborBlue,
        secondary: sealGold,
        surface: palette.card,
        onSurface: palette.ink,
      ),
      scaffoldBackgroundColor: palette.paper,
    );

    return base.copyWith(
      extensions: [palette],
      // Pin body/display colours to the palette rather than letting Material
      // pick near-black or pure white -- the site's own surfaces are warm
      // paper and deep navy, and Material's defaults sit wrong on both.
      textTheme: base.textTheme.apply(
        bodyColor: palette.ink,
        displayColor: palette.ink,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(color: palette.border),
      iconTheme: IconThemeData(color: palette.ink),
    );
  }

  static ThemeData get light => themeFor(Brightness.light);
  static ThemeData get dark => themeFor(Brightness.dark);
}

/// The surfaces and text colours that invert between light and dark.
@immutable
class WebPalette extends ThemeExtension<WebPalette> {
  const WebPalette({
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

  /// The alternating section background that breaks up a long page.
  final Color foam;

  /// Card and raised-surface fill.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text -- captions, metadata, helper lines.
  final Color inkMuted;

  final Color border;

  /// Lets a widget pick a different asset or elevation for dark without
  /// re-deriving it from a colour comparison.
  final bool isDark;

  static const light = WebPalette(
    paper: Color(0xFFF7F5F0),
    foam: Color(0xFFEAF3F5),
    card: Colors.white,
    ink: Color(0xFF0B2545),
    inkMuted: Color(0xFF5A6675),
    border: Color(0xFFE3DFD3),
    isDark: false,
  );

  /// Not a pure-black dark mode: the navy the brand already uses is carried
  /// down into the backgrounds so the dark site still reads as the same
  /// product, and large text stays off-white rather than #FFF to keep the
  /// contrast comfortable on a bright screen.
  static const dark = WebPalette(
    paper: Color(0xFF0A1826),
    foam: Color(0xFF102434),
    card: Color(0xFF15293B),
    ink: Color(0xFFEDF2F7),
    inkMuted: Color(0xFF9AAABC),
    border: Color(0xFF23384C),
    isDark: true,
  );

  @override
  WebPalette copyWith({
    Color? paper,
    Color? foam,
    Color? card,
    Color? ink,
    Color? inkMuted,
    Color? border,
    bool? isDark,
  }) {
    return WebPalette(
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
  WebPalette lerp(ThemeExtension<WebPalette>? other, double t) {
    if (other is! WebPalette) return this;
    return WebPalette(
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
