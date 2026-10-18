import 'package:flutter/material.dart';
import 'brand_fonts.dart';

import 'brand_theme.dart';
import 'brand_tokens.dart';

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
  static const inkNavy = BrandColors.inkNavy;
  static const harborBlue = BrandColors.harborBlue;
  static const sealGold = BrandColors.sealGold;
  static const deepTeal = BrandColors.deepTeal;

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
    return BrandFonts.display(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
  }

  static TextStyle heroDisplay({Color color = Colors.white}) {
    return BrandFonts.display(fontSize: 48, fontWeight: FontWeight.w600, color: color, height: 1.1);
  }

  /// Gold small caps for a fixed navy background (the hero, the footer).
  /// On a page that follows the mode use [eyebrowFor]: this gold is only
  /// 2.4:1 on the light paper.
  static const TextStyle eyebrow = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    color: sealGold,
  );

  /// Component styling is shared with the app and admin portal
  /// ([BrandTheme]); the website only adds its own palette extension.
  static ThemeData themeFor(Brightness brightness) {
    final palette = brightness == Brightness.dark ? WebPalette.dark : WebPalette.light;
    return BrandTheme.build(brightness, extensions: [palette]);
  }

  /// Eyebrow for a surface that follows light/dark: the darker gold ink in
  /// light mode (5.3:1), the bright seal gold in dark mode.
  static TextStyle eyebrowFor(BuildContext context) => eyebrow.copyWith(
        color: Theme.of(context).brightness == Brightness.dark ? sealGold : BrandColors.sealGoldInk,
      );

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

  static final light = WebPalette.fromSurfaces(BrandSurfaces.light, isDark: false);

  /// Not a pure-black dark mode: the navy the brand already uses is carried
  /// down into the backgrounds so the dark site still reads as the same
  /// product, and large text stays off-white rather than #FFF to keep the
  /// contrast comfortable on a bright screen.
  static final dark = WebPalette.fromSurfaces(BrandSurfaces.dark, isDark: true);

  /// Built from the shared tokens so the website's surfaces can never drift
  /// from the app's and the admin portal's again.
  factory WebPalette.fromSurfaces(BrandSurfaces s, {required bool isDark}) => WebPalette(
        paper: s.paper,
        foam: s.foam,
        card: s.card,
        ink: s.ink,
        inkMuted: s.inkMuted,
        border: s.border,
        isDark: isDark,
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
