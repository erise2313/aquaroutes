import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/app_colors.dart';
import 'package:aquaroute/constants/app_palette.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/constants/web_theme.dart';
import 'package:aquaroute/providers/app_theme_provider.dart';
import 'package:aquaroute/screens/app_route.dart';

/// Resolves the theme the way a screen actually sees it -- from a pumped
/// widget tree rather than by constructing `AppTheme.light` in a bare
/// `test()`.
///
/// `GoogleFonts.fraunces` kicks off an unawaited font load the first time a
/// display style is built. In a bare `test()` there is no widget lifecycle for
/// that future to settle in, so it rejects after the test finishes and
/// flutter_test reports "this test failed after it had already completed"
/// even though every assertion passed. Pumping and settling gives it
/// somewhere to land. Production is untouched: the website and admin portal
/// already load Fraunces exactly this way.
Future<ThemeData> _appliedTheme(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
  late ThemeData resolved;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.themeFor(brightness),
    home: Builder(builder: (context) {
      resolved = Theme.of(context);
      return const Scaffold(body: Text('probe'));
    }),
  ));
  await tester.pumpAndSettle();
  return resolved;
}

/// Contrast ratio (WCAG). Used to check text stays readable on its own
/// surface in both modes, rather than eyeballing hex values.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppTheme', () {
    // AdminTheme used textTheme.apply(fontSizeFactor:), which asserts in debug
    // and silently no-ops in release because ThemeData's text theme carries no
    // sizes at construction time. Every style here must have a real size.
    testWidgets('every text style has an explicit size', (tester) async {
      final t = (await _appliedTheme(tester)).textTheme;
      final styles = <String, TextStyle?>{
        'headlineLarge': t.headlineLarge, 'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall, 'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium, 'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge, 'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall, 'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium, 'labelSmall': t.labelSmall,
      };
      styles.forEach((name, style) {
        expect(style?.fontSize, isNotNull, reason: '$name has no explicit size');
      });
    });

    testWidgets('light mode is on the brand surface, with brand ink', (tester) async {
      final theme = await _appliedTheme(tester);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppColors.surface);
      expect(theme.textTheme.bodyMedium!.color, AppColors.ink);
    });

    testWidgets('type scale is monotonic from body to headline', (tester) async {
      final t = (await _appliedTheme(tester)).textTheme;
      expect(t.bodySmall!.fontSize!, lessThan(t.bodyMedium!.fontSize!));
      expect(t.bodyMedium!.fontSize!, lessThan(t.bodyLarge!.fontSize!));
      expect(t.titleLarge!.fontSize!, lessThan(t.headlineSmall!.fontSize!));
      expect(t.headlineSmall!.fontSize!, lessThan(t.headlineMedium!.fontSize!));
      expect(t.headlineMedium!.fontSize!, lessThan(t.headlineLarge!.fontSize!));
    });

    // Gold means accreditation across the website and admin portal. If it
    // becomes a general-purpose accent here it stops meaning anything.
    testWidgets('seal gold is the secondary, not the primary accent', (tester) async {
      final theme = await _appliedTheme(tester);
      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.colorScheme.secondary, AppColors.seal);
    });

    // One radius, after eleven different values were in use across the app.
    testWidgets('cards and buttons share one radius', (tester) async {
      final theme = await _appliedTheme(tester);
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.borderRadius, BorderRadius.circular(AppTheme.radius));
    });
  });

  group('AppTheme dark', () {
    testWidgets('actually inverts surfaces and text', (tester) async {
      final light = await _appliedTheme(tester);
      final dark = await _appliedTheme(tester, brightness: Brightness.dark);

      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor.computeLuminance(),
          lessThan(light.scaffoldBackgroundColor.computeLuminance()));
      expect(dark.textTheme.bodyMedium!.color!.computeLuminance(),
          greaterThan(light.textTheme.bodyMedium!.color!.computeLuminance()));
    });

    testWidgets('text stays readable against its own background in both modes', (tester) async {
      for (final brightness in Brightness.values) {
        final theme = await _appliedTheme(tester, brightness: brightness);
        final palette = theme.extension<AppPalette>()!;
        expect(_contrast(palette.ink, palette.paper), greaterThan(7.0), reason: 'body text on the page, $brightness');
        expect(_contrast(palette.ink, palette.card), greaterThan(7.0), reason: 'body text on a card, $brightness');
        expect(_contrast(palette.inkMuted, palette.card), greaterThan(4.5), reason: 'muted text on a card, $brightness');
      }
    });

    testWidgets('both palettes are registered so widgets can read them', (tester) async {
      for (final brightness in Brightness.values) {
        final theme = await _appliedTheme(tester, brightness: brightness);
        expect(theme.extension<AppPalette>()?.isDark, brightness == Brightness.dark);
        expect(theme.extension<DriverPalette>()?.isDark, brightness == Brightness.dark);
      }
    });

    // The driver portal is read at arm's length in a moving vehicle, so its
    // own palette has to clear contrast in whichever mode it follows.
    test('the driver palette stays high-contrast in both modes', () {
      for (final palette in [DriverPalette.dark, DriverPalette.light]) {
        expect(_contrast(palette.text, palette.background), greaterThan(7.0));
        expect(_contrast(palette.text, palette.surface), greaterThan(7.0));
        expect(_contrast(palette.textMuted, palette.surface), greaterThan(4.5));
        expect(_contrast(palette.onDuty, palette.surface), greaterThan(3.0));
        expect(_contrast(palette.alert, palette.surface), greaterThan(3.0));
      }
    });
  });

  group('appThemeDataFor', () {
    test('follows the phone only when the mode says to', () {
      expect(appThemeDataFor(AppThemeMode.system, Brightness.dark).brightness, Brightness.dark);
      expect(appThemeDataFor(AppThemeMode.system, Brightness.light).brightness, Brightness.light);
      expect(appThemeDataFor(AppThemeMode.light, Brightness.dark).brightness, Brightness.light);
      expect(appThemeDataFor(AppThemeMode.dark, Brightness.light).brightness, Brightness.dark);
    });
  });

  group('appRoute', () {
    Widget hostUnder(ThemeData rootTheme, void Function(BuildContext) probe, {Brightness? platform}) {
      final app = MaterialApp(
        theme: rootTheme,
        home: Builder(builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(context, appRoute(Builder(builder: (c) {
              probe(c);
              return const SizedBox();
            }))),
            child: const Text('go'),
          ),
        )),
      );
      return ProviderScope(
        child: platform == null
            ? app
            : MediaQuery(data: MediaQueryData(platformBrightness: platform), child: app),
      );
    }

    // The live bug this fixes: the website's theme reaches every surface, so a
    // visitor who switched the public site to dark and then signed in as a
    // station owner got the merchant portal on a dark page. A shell-level
    // Theme does not reach pushed screens, so this is what actually closes it.
    testWidgets('a pushed screen takes the app theme, not the website root', (tester) async {
      Color? background;
      Brightness? brightness;
      await tester.pumpWidget(hostUnder(WebTheme.dark, (c) {
        background = Theme.of(c).scaffoldBackgroundColor;
        brightness = Theme.of(c).brightness;
      }));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(brightness, Brightness.light, reason: 'pushed app screen went dark');
      expect(background, AppColors.surface);
    });

    testWidgets('a pushed screen follows the phone into dark mode', (tester) async {
      Brightness? brightness;
      await tester.pumpWidget(hostUnder(AppTheme.light, (c) {
        brightness = Theme.of(c).brightness;
      }, platform: Brightness.dark));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(brightness, Brightness.dark, reason: 'the phone is in dark mode, so the pushed screen should be too');
    });
  });

  group('ambientRoute', () {
    // bulletin_feed is embedded in admin, merchant, driver, the customer app
    // and the website's news page. Pinning its pushes to AppTheme would hand a
    // dark-mode website visitor a light login screen, so it captures instead.
    testWidgets('carries whatever theme was ambient at the push site', (tester) async {
      Brightness? pushed;

      await tester.pumpWidget(MaterialApp(
        theme: WebTheme.light,
        home: Theme(
          data: WebTheme.dark, // a dark website page hosting the shared widget
          child: Builder(builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(context, ambientRoute(context, Builder(builder: (c) {
                pushed = Theme.of(c).brightness;
                return const SizedBox();
              }))),
              child: const Text('go'),
            ),
          )),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(pushed, Brightness.dark, reason: 'shared widget should not force light on a dark host');
    });
  });
}
