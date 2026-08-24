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
class WebTheme {
  WebTheme._();

  static const inkNavy = Color(0xFF0B2545);
  static const harborBlue = Color(0xFF1565C0); // same blue as AppColors.primary -- same brand
  static const deepTeal = Color(0xFF0B4F5C);
  static const sealGold = Color(0xFFC99A3B);
  static const paper = Color(0xFFF7F5F0);
  static const foam = Color(0xFFEAF3F5);

  /// Fraunces for display/heading type -- the one deliberate typographic
  /// choice; body text stays the default system sans everywhere else.
  static TextStyle display({double fontSize = 28, FontWeight fontWeight = FontWeight.w600, Color color = inkNavy, double? height}) {
    return GoogleFonts.fraunces(fontSize: fontSize, fontWeight: fontWeight, color: color, height: height);
  }

  static TextStyle heroDisplay({Color color = Colors.white}) {
    return GoogleFonts.fraunces(fontSize: 48, fontWeight: FontWeight.w600, color: color, height: 1.1);
  }

  static const TextStyle eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.2,
    color: sealGold,
  );
}
