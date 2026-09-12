import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/admin_theme.dart';

/// Light or dark for the WASA Admin portal -- an explicit choice, never the
/// browser's.
///
/// The mobile app follows the phone because that's what a phone user
/// expects. Admin is a desk tool used by association officers, and a PC set
/// to dark shouldn't silently change how the portal looks the first time
/// they open it; they pick it from the header and it stays picked, per
/// browser.
enum AdminThemeMode {
  light,
  dark;

  Brightness get brightness => this == AdminThemeMode.dark ? Brightness.dark : Brightness.light;
}

ThemeData adminThemeDataFor(AdminThemeMode mode) => AdminTheme.themeFor(mode.brightness);

const _prefsKey = 'admin_theme_mode';

class AdminThemeNotifier extends Notifier<AdminThemeMode> {
  @override
  AdminThemeMode build() {
    // Starts light and loads the stored choice immediately after: reading
    // preferences is async, and blocking the first frame on it would be
    // worse than a brief flash of the default.
    _restore();
    return AdminThemeMode.light;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKey) == AdminThemeMode.dark.name) state = AdminThemeMode.dark;
    } catch (_) {
      // Blocked site data just means the portal opens light.
    }
  }

  Future<void> toggle() => set(state == AdminThemeMode.light ? AdminThemeMode.dark : AdminThemeMode.light);

  Future<void> set(AdminThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // The choice still applies for this session; it just isn't remembered.
    }
  }
}

final adminThemeProvider = NotifierProvider<AdminThemeNotifier, AdminThemeMode>(AdminThemeNotifier.new);
