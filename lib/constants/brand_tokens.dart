import 'package:flutter/material.dart';

/// The one set of design tokens behind the app, the public website and the
/// admin portal.
///
/// Before this file each surface had its own theme with its own copies of
/// the same hex values (app_theme.dart, web_theme.dart, admin_theme.dart),
/// and they had drifted: admin sat on a blue-grey page with shadowed cards
/// and a navy band on every page, the app on warm paper with bordered cards.
/// The evaluation found the result read as three products. The app's look is
/// the one people liked, so these values are the app's, and the three themes
/// now read from here.
///
/// Contrast targets (WCAG AAA), checked in test/brand_tokens_test.dart:
///  * every colour used as text -- body, muted, the brand blue, status inks,
///    gold labels -- 7:1 on every surface, in light AND dark mode
///  * text on the brand-blue buttons: 7:1
///  * input outlines: 3:1 (non-text UI component)
/// Raised from AA (4.5:1) in October 2026 for older readers, per the UI plan;
/// the hues are the same, only darker (light) or lighter (dark).
class BrandColors {
  BrandColors._();

  // -- Brand accents, identical in both modes ----------------------------
  static const inkNavy = Color(0xFF0B2545);
  /// Was #1565C0 (5.1-5.7:1 as text); this is 7.7:1 on every light surface
  /// and white text on it is 8.6:1.
  static const harborBlue = Color(0xFF0D47A1);

  /// Accreditation only. Never a general accent, or it stops meaning anything.
  static const sealGold = Color(0xFFC99A3B);

  /// Gold for *text* on a light surface -- the decorative gold is 2.4:1 on
  /// paper, which no one can read.
  static const sealGoldInk = Color(0xFF654A0D);

  /// Gold for text on a dark surface; the decorative gold is 5.8:1 there.
  static const sealGoldInkDark = Color(0xFFE0BC6A);

  static const deepTeal = Color(0xFF0B4F5C);

  /// Gold that can be read as text on the current surface.
  static Color sealGoldTextFor(Brightness b) => b == Brightness.dark ? sealGoldInkDark : sealGoldInk;

  /// The brand blue lifted for dark surfaces (8:1 on every dark surface).
  static const harborBlueOnDark = Color(0xFF8CC4F5);
  static const onHarborBlueOnDark = Color(0xFF04243F);
}

/// Status colours as *fills* (pills, dots, chart series) and as *ink* (text
/// and icons that must be read). They differ because the bright fills fail
/// as text -- the pending amber is 1.8:1 on paper.
class BrandStatus {
  BrandStatus._();

  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFF9A825);
  static const danger = Color(0xFFC62828);
  static const info = BrandColors.harborBlue;

  static const successInk = Color(0xFF19571C);
  static const warningInk = Color(0xFF6E4100);
  static const dangerInk = Color(0xFF9F1C1C);

  static const successInkDark = Color(0xFF81C784);
  static const warningInkDark = Color(0xFFFFCA28);
  static const dangerInkDark = Color(0xFFFFAB91);

  static Color successFor(Brightness b) => b == Brightness.dark ? successInkDark : successInk;
  static Color warningFor(Brightness b) => b == Brightness.dark ? warningInkDark : warningInk;
  static Color dangerFor(Brightness b) => b == Brightness.dark ? dangerInkDark : dangerInk;
}

/// Surfaces and text that invert between modes. The three palette
/// extensions (AppPalette, WebPalette, AdminPalette) are all built from one
/// of these two, so the surfaces can never drift apart again.
@immutable
class BrandSurfaces {
  const BrandSurfaces({
    required this.paper,
    required this.foam,
    required this.card,
    required this.ink,
    required this.inkMuted,
    required this.border,
    required this.inputBorder,
  });

  /// Page background.
  final Color paper;

  /// Tinted background: alternating bands, callouts, the sidebar.
  final Color foam;

  /// Cards and raised surfaces.
  final Color card;

  /// Primary text.
  final Color ink;

  /// Secondary text -- captions, metadata, helper lines.
  final Color inkMuted;

  /// Decorative dividers and card outlines.
  final Color border;

  /// Outlines that must be *seen* (text fields, checkboxes): 3:1 minimum.
  final Color inputBorder;

  static const light = BrandSurfaces(
    paper: Color(0xFFF7F5F0),
    foam: Color(0xFFEAF3F5),
    card: Colors.white,
    ink: BrandColors.inkNavy,
    // Was #5A6675 (5.4:1 on paper). Most officers and owners are older
    // readers; this clears 7:1 on paper, card and foam.
    inkMuted: Color(0xFF434D5A),
    border: Color(0xFFE3DFD3),
    inputBorder: Color(0xFF8C8678),
  );

  /// Navy carried into the backgrounds rather than pure black, so the dark
  /// mode is still the same product; off-white text to stay comfortable.
  static const dark = BrandSurfaces(
    paper: Color(0xFF0A1826),
    foam: Color(0xFF102434),
    card: Color(0xFF15293B),
    ink: Color(0xFFEDF2F7),
    inkMuted: Color(0xFFA9B7C6),
    border: Color(0xFF23384C),
    inputBorder: Color(0xFF6B8199),
  );

  static BrandSurfaces of(Brightness brightness) => brightness == Brightness.dark ? dark : light;
}

/// One radius pair for everything. The codebase once had eleven.
class BrandRadius {
  BrandRadius._();
  static const double card = 12;
  static const double control = 8;
  static const double pill = 999;
}

/// The spacing rhythm. Screens should use these rather than ad-hoc values.
class BrandSpace {
  BrandSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Type sizes shared by all three surfaces.
///
/// Body text is 18 and nothing anywhere goes below 16 -- captions, table
/// cells and helper lines included. Most of the people who must succeed
/// with the product are older readers (presbyopia, lower contrast
/// sensitivity), so this follows the senior-focused guidance in the UI
/// plan rather than the usual 14-16 defaults. It was 16 body / 13 minimum.
class BrandType {
  BrandType._();
  static const double headlineLarge = 34;
  static const double headlineMedium = 29;
  static const double headlineSmall = 25;
  static const double titleLarge = 22;
  static const double titleMedium = 19;
  static const double titleSmall = 18;
  static const double bodyLarge = 20;
  static const double bodyMedium = 18;
  static const double bodySmall = 16;
  static const double labelLarge = 18;
  static const double labelMedium = 16;
  static const double labelSmall = 16;

  /// Minimum height of anything tappable.
  static const double minTarget = 48;

  /// Minimum height of a screen's main (filled) button.
  static const double minPrimaryTarget = 56;
}
