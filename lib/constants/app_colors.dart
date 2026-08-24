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
