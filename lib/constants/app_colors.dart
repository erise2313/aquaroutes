import 'package:flutter/material.dart';

/// Central color palette. Replaces the old pattern of hardcoding
/// `Colors.blue.shade600` etc. inline in every screen.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1565C0);
  static const Color accent = Color(0xFF00ACC1);

  static const Color cleared = Color(0xFF2E7D32);
  static const Color pendingClearance = Color(0xFFF9A825);
  static const Color flagged = Color(0xFFC62828);

  static const Color alkalineGlowCyan = Color(0xFF00E5FF);
  static const Color alkalineGlowPurple = Color(0xFF9C27B0);

  // -- Surfaces and text -------------------------------------------------
  //
  // Added because this file was only ever a *status* palette: primary,
  // accent, three clearance states, driver colors. It had no surface or text
  // tokens, so merchant and customer screens had nothing to reach for and
  // fell back to Colors.grey.shade700 / Colors.white / Colors.blue ~260
  // times between them. That absence is why those two surfaces look like
  // stock Material while the website and admin portal look like a product.
  //
  // The values are the ones the website and admin already use (web_theme.dart
  // and admin_theme.dart), so the app surfaces join the identity that exists
  // rather than inventing a third one. Nothing above this line changed --
  // adding tokens can't shift anything that already renders correctly.

  /// Primary text. Same ink navy the website and admin portal use.
  static const Color ink = Color(0xFF0B2545);

  /// Secondary text -- captions, metadata, helper lines. Replaces the
  /// Colors.grey.shade600/700 that carried this job by default.
  static const Color inkMuted = Color(0xFF5A6675);

  /// Page background. Warm paper rather than pure white, matching the site.
  static const Color surface = Color(0xFFF7F5F0);

  /// Tinted background for callouts and alternating blocks.
  static const Color surfaceAlt = Color(0xFFEAF3F5);

  /// Card and raised-surface fill.
  static const Color card = Colors.white;

  static const Color border = Color(0xFFE3DFD3);

  /// The association's seal gold. Reserved for accreditation and
  /// verification, exactly as on the website and in admin -- it should never
  /// become a general-purpose accent, or it stops meaning anything.
  static const Color seal = Color(0xFFC99A3B);

  /// High-contrast palette for the Driver/Helper portal (daylight-road
  /// readability -- large targets, strong contrast, not the default
  /// Material blue theme used by the owner/admin portals).
  static const Color driverBackground = Color(0xFF0D1117);
  static const Color driverSurface = Color(0xFF161B22);
  static const Color driverOnDuty = Color(0xFF00C853);
  static const Color driverOffDuty = Color(0xFF616161);
  static const Color driverAlert = Color(0xFFFF3D00);
  static const Color driverText = Color(0xFFFFFFFF);
}
