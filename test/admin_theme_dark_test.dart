import 'package:aquaroute/constants/admin_palette.dart';
import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/providers/admin_theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resolves the admin theme from a pumped widget, not a bare `test()`:
/// AdminTheme builds Fraunces styles through GoogleFonts, whose font load
/// needs a widget lifecycle to settle in (see the note in app_theme_test.dart).
Future<ThemeData> _adminTheme(WidgetTester tester, Brightness brightness) async {
  late ThemeData resolved;
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.themeFor(brightness),
    home: Builder(builder: (context) {
      resolved = Theme.of(context);
      return const Scaffold(body: Text('probe'));
    }),
  ));
  await tester.pumpAndSettle();
  return resolved;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AdminTheme', () {
    testWidgets('dark actually inverts the portal surfaces and text', (tester) async {
      final light = await _adminTheme(tester, Brightness.light);
      final dark = await _adminTheme(tester, Brightness.dark);

      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor.computeLuminance(),
          lessThan(light.scaffoldBackgroundColor.computeLuminance()));
      expect(dark.textTheme.bodyMedium!.color!.computeLuminance(),
          greaterThan(light.textTheme.bodyMedium!.color!.computeLuminance()));
    });

    testWidgets('the palette is registered in both modes', (tester) async {
      for (final brightness in Brightness.values) {
        final theme = await _adminTheme(tester, brightness);
        expect(theme.extension<AdminPalette>()?.isDark, brightness == Brightness.dark);
      }
    });

    // Admin's users skew older, so this theme exists partly to be larger and
    // higher contrast than Material's defaults. That has to survive dark mode.
    testWidgets('admin type stays larger than the Material default', (tester) async {
      for (final brightness in Brightness.values) {
        final theme = await _adminTheme(tester, brightness);
        expect(theme.textTheme.bodyMedium?.fontSize, isNotNull);
        expect(theme.textTheme.bodyMedium!.fontSize!, greaterThan(14.0));
      }
    });

    test('text is readable on its own surfaces in both modes', () {
      for (final palette in [AdminPalette.light, AdminPalette.dark]) {
        expect(_contrast(palette.ink, palette.paper), greaterThan(7.0));
        expect(_contrast(palette.ink, palette.card), greaterThan(7.0));
        expect(_contrast(palette.ink, palette.foam), greaterThan(7.0));
        expect(_contrast(palette.inkMuted, palette.card), greaterThan(4.5));
      }
    });

    // The header band stays navy in both modes -- it carries the portal's
    // identity, and the sweep that moved body colours onto the palette
    // deliberately left anything drawn on that band white.
    test('the navy header band keeps white text legible', () {
      expect(AdminTheme.headerBand, AdminTheme.inkNavy);
      expect(_contrast(Colors.white, AdminTheme.headerBand), greaterThan(7.0));
      expect(_contrast(Colors.white70, AdminTheme.headerBand), greaterThan(4.5));
      expect(_contrast(AdminTheme.sealGold, AdminTheme.headerBand), greaterThan(3.0));
    });
  });

  group('adminThemeDataFor', () {
    // Manual only, by decision: an officer's PC set to dark shouldn't change
    // how the portal looks without them asking.
    testWidgets('maps the chosen mode, ignoring the browser', (tester) async {
      late Brightness light;
      late Brightness dark;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: Builder(builder: (context) {
          light = adminThemeDataFor(AdminThemeMode.light).brightness;
          dark = adminThemeDataFor(AdminThemeMode.dark).brightness;
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();

      expect(light, Brightness.light, reason: 'a dark browser must not force the portal dark');
      expect(dark, Brightness.dark);
    });
  });
}
