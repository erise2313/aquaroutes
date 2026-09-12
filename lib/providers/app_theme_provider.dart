import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_theme.dart';

/// Light / dark for the app's customer, owner and driver portals.
///
/// Unlike the website (providers/web_theme_provider.dart), the default here
/// **is** the phone's setting: that is what a phone user expects and what
/// Android's quality guidelines ask for. Someone who wants to override it
/// can, from Account settings.
enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode get material => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };

  String get label => switch (this) {
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.system => 'Follow phone',
      };
}

/// The theme a screen should use right now.
///
/// Needed because a pushed route and the portal shells build their own
/// `Theme` (the root MaterialApp's themeMode doesn't reach them on the
/// website build, where the root is the site's own theme).
ThemeData appThemeDataFor(AppThemeMode mode, Brightness platformBrightness) {
  final brightness = switch (mode) {
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
    AppThemeMode.system => platformBrightness,
  };
  return AppTheme.themeFor(brightness);
}

const _prefsKey = 'app_theme_mode';

class AppThemeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    // Starts on the phone's setting and loads any stored override right
    // after; reading preferences is async and blocking the first frame on
    // it would be worse than a brief default.
    _restore();
    return AppThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      for (final mode in AppThemeMode.values) {
        if (mode.name == stored) state = mode;
      }
    } catch (_) {
      // Storage unavailable (private browsing, blocked site data) just means
      // the app follows the phone.
    }
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // The choice still applies for this session; it just isn't remembered.
    }
  }
}

final appThemeProvider = NotifierProvider<AppThemeNotifier, AppThemeMode>(AppThemeNotifier.new);
