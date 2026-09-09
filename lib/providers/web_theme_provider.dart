import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light/dark for the public website -- an explicit choice, never
/// `ThemeMode.system`.
///
/// Following the browser was the previous behaviour and it was wrong for this
/// site: the pages paint their own warm-paper and navy surfaces from
/// [WebPalette], so a visitor whose OS happened to be in dark mode got
/// Material's dark text colours on the site's light backgrounds. Owning the
/// choice means the two modes are both designed, rather than one of them
/// being an accident of someone's system settings.
enum WebThemeMode {
  light,
  dark;

  ThemeMode get material => this == WebThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
}

const _prefsKey = 'web_theme_mode';

class WebThemeNotifier extends Notifier<WebThemeMode> {
  @override
  WebThemeMode build() {
    // Starts light and loads the stored preference immediately after. The
    // first frame therefore paints light even for someone who chose dark,
    // which is a brief flash rather than a wrong-forever default; reading
    // prefs is async and blocking the first frame on it would be worse.
    _restore();
    return WebThemeMode.light;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored == WebThemeMode.dark.name) state = WebThemeMode.dark;
    } catch (_) {
      // Storage being unavailable (private browsing, blocked site data) is
      // not worth failing over -- the site just opens in light mode.
    }
  }

  Future<void> toggle() => set(state == WebThemeMode.light ? WebThemeMode.dark : WebThemeMode.light);

  Future<void> set(WebThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // The toggle still worked for this session; it just won't be remembered.
    }
  }
}

final webThemeProvider = NotifierProvider<WebThemeNotifier, WebThemeMode>(WebThemeNotifier.new);
