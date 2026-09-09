import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/app_colors.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/constants/web_theme.dart';
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
Future<ThemeData> _appliedTheme(WidgetTester tester) async {
  late ThemeData resolved;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(builder: (context) {
      resolved = Theme.of(context);
      return const Scaffold(body: Text('probe'));
    }),
  ));
  await tester.pumpAndSettle();
  return resolved;
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

    testWidgets('is light, on the brand surface, with brand ink', (tester) async {
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

  group('appRoute', () {
    // The live bug this fixes: main.dart hands the website's theme to every
    // surface, so a visitor who switched the public site to dark and then
    // signed in as a station owner got the merchant portal on a dark page. A
    // shell-level Theme does not reach pushed screens, so this is what
    // actually closes it.
    testWidgets('a pushed screen keeps the app theme even under a dark root', (tester) async {
      Color? pushedBackground;
      Brightness? pushedBrightness;

      await tester.pumpWidget(MaterialApp(
        theme: WebTheme.dark, // the root a dark-mode visitor carries in
        home: Builder(builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(context, appRoute(Builder(builder: (c) {
              pushedBackground = Theme.of(c).scaffoldBackgroundColor;
              pushedBrightness = Theme.of(c).brightness;
              return const SizedBox();
            }))),
            child: const Text('go'),
          ),
        )),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(pushedBrightness, Brightness.light, reason: 'pushed app screen went dark');
      expect(pushedBackground, AppColors.surface);
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
