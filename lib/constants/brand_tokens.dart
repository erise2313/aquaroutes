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
/// Contrast targets (WCAG), checked in test/brand_tokens_test.dart:
///  * body and muted text: 7:1 on every surface in light mode, 4.5:1+ in dark
///  * status colours used as text: 4.5:1 on paper and card in both modes
///  * input outlines: 3:1 (non-text UI component)
class BrandColors {
  BrandColors._();

  // -- Brand accents, identical in both modes ----------------------------
  static const inkNavy = Color(0xFF0B2545);
  static const harborBlue = Color(0xFF1565C0);

  /// Accreditation only. Never a general accent, or it stops meaning anything.
  static const sealGold = Color(0xFFC99A3B);

  /// Gold for *text* on a light surface -- the decorative gold is 2.4:1 on
  /// paper, which no one can read.
  static const sealGoldInk = Color(0xFF8A6516);

  static const deepTeal = Color(0xFF0B4F5C);

  /// The brand blue lifted for dark surfaces (7.9:1 on the dark page).
  static const harborBlueOnDark = Color(0xFF6FB1F0);
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

  static const successInk = Color(0xFF2E7D32);
  static const warningInk = Color(0xFF8A5A00);
  static const dangerInk = Color(0xFFC62828);

  static const successInkDark = Color(0xFF66BB6A);
  static const warningInkDark = Color(0xFFFFCA28);
  static const dangerInkDark = Color(0xFFFF8A80);

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

/// Type sizes shared by all three surfaces. Body is 16 (it was 14.5 in the
/// app): the evaluation's users are mostly older readers, and nothing a
/// person must read goes below 13.
class BrandType {
  BrandType._();
  static const double headlineLarge = 32;
  static const double headlineMedium = 27;
  static const double headlineSmall = 23;
  static const double titleLarge = 20;
  static const double titleMedium = 17;
  static const double titleSmall = 15;
  static const double bodyLarge = 17;
  static const double bodyMedium = 16;
  static const double bodySmall = 14;
  static const double labelLarge = 15.5;
  static const double labelMedium = 14;
  static const double labelSmall = 13;

  /// Minimum height of anything tappable.
  static const double minTarget = 48;
}
