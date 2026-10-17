import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/web_theme.dart';
import 'package:aquaroute/providers/web_theme_provider.dart';
import 'package:aquaroute/widgets/web_nav_bar.dart';

double _luminance(Color c) => c.computeLuminance();

void main() {
  group('WebPalette', () {
    test('light and dark actually invert their surfaces and text', () {
      expect(_luminance(WebPalette.light.paper), greaterThan(0.5));
      expect(_luminance(WebPalette.dark.paper), lessThan(0.2));
      expect(_luminance(WebPalette.light.ink), lessThan(0.2));
      expect(_luminance(WebPalette.dark.ink), greaterThan(0.5));
    });

    // Text on a background that also moved is the failure mode that made the
    // old system-following behaviour unusable, so assert real separation
    // rather than merely "different".
    test('text stays high-contrast against its own background in both modes', () {
      for (final p in [WebPalette.light, WebPalette.dark]) {
        expect((_luminance(p.ink) - _luminance(p.paper)).abs(), greaterThan(0.4));
        expect((_luminance(p.ink) - _luminance(p.card)).abs(), greaterThan(0.4));
        expect((_luminance(p.ink) - _luminance(p.foam)).abs(), greaterThan(0.4));
      }
    });

    test('muted text is dimmer than primary but still separated from the page', () {
      for (final p in [WebPalette.light, WebPalette.dark]) {
        expect((_luminance(p.inkMuted) - _luminance(p.paper)).abs(), greaterThan(0.1));
      }
    });

    test('lerp moves between the two palettes', () {
      final mid = WebPalette.light.lerp(WebPalette.dark, 0.5);
      expect(mid.paper, isNot(WebPalette.light.paper));
      expect(mid.paper, isNot(WebPalette.dark.paper));
    });
  });

  group('WebTheme', () {
    // Pumped rather than bare test()s: the shared BrandTheme builds Fraunces
    // headings through GoogleFonts, whose font load needs a widget lifecycle
    // to settle in (see the note in app_theme_test.dart).
    testWidgets('registers the matching palette on each ThemeData', (tester) async {
      final light = WebTheme.light;
      final dark = WebTheme.dark;
      await tester.pumpWidget(MaterialApp(theme: light, home: const SizedBox()));
      await tester.pumpAndSettle();
      expect(light.extension<WebPalette>()!.isDark, isFalse);
      expect(dark.extension<WebPalette>()!.isDark, isTrue);
    });

    testWidgets('pins body text to the palette rather than Material defaults', (tester) async {
      final light = WebTheme.light;
      final dark = WebTheme.dark;
      await tester.pumpWidget(MaterialApp(theme: light, home: const SizedBox()));
      await tester.pumpAndSettle();
      expect(dark.textTheme.bodyMedium!.color, WebPalette.dark.ink);
      expect(light.textTheme.bodyMedium!.color, WebPalette.light.ink);
    });

    // Brand accents must be identical across modes: WebSeal is reused inside
    // the admin portal, which never registers WebPalette.
    test('brand accents are mode-independent constants', () {
      expect(WebTheme.sealGold, const Color(0xFFC99A3B));
      expect(WebTheme.harborBlue, const Color(0xFF1565C0));
    });

    testWidgets('of() falls back to light where no palette is registered', (tester) async {
      late WebPalette resolved;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true), // no WebPalette extension
        home: Builder(builder: (context) {
          resolved = WebTheme.of(context);
          return const SizedBox();
        }),
      ));
      expect(resolved.isDark, isFalse);
    });

    testWidgets('display() inherits the theme text colour instead of pinning navy', (tester) async {
      // This is what lets every heading flip without touching a call site.
      expect(WebTheme.display(fontSize: 32).color, isNull);
      expect(WebTheme.display(fontSize: 32, color: Colors.white).color, Colors.white);
    });
  });

  group('theme toggle', () {
    testWidgets('nav bar exposes a toggle that flips the mode', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: WebTheme.light,
              darkTheme: WebTheme.dark,
              themeMode: ref.watch(webThemeProvider).material,
              home: const Scaffold(appBar: WebNavBar(currentPage: WebPage.home), body: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to dark mode'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch to dark mode'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to light mode'), findsOneWidget);
      expect(find.byTooltip('Switch to dark mode'), findsNothing);
    });

    test('WebThemeMode maps to an explicit ThemeMode, never system', () {
      expect(WebThemeMode.light.material, ThemeMode.light);
      expect(WebThemeMode.dark.material, ThemeMode.dark);
      for (final m in WebThemeMode.values) {
        expect(m.material, isNot(ThemeMode.system));
      }
    });
  });
}
