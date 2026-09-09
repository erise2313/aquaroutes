import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/widgets/web_nav_bar.dart';
import 'package:aquaroute/widgets/wasa_shield_logo.dart';

Widget _harness() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(appBar: WebNavBar(currentPage: WebPage.home), body: SizedBox()),
      ),
    );

const _navLabels = ['Home', 'About', 'Accreditation', 'For Owners', 'News', 'Stations', 'Contact'];

void main() {
  // The nav used to be full-bleed while the page sections below sit in a
  // centred column, so on a wide monitor the actions ended in a large
  // unexplained gap on the right with none on the left.
  testWidgets('nav margins are symmetric on a wide viewport', (tester) async {
    tester.view.physicalSize = const Size(1920, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final logoLeft = tester.getRect(find.byType(WasaShieldLogo)).left;
    final rightmost = find.widgetWithText(ElevatedButton, 'Register a Station');
    expect(rightmost, findsOneWidget, reason: 'the primary CTA should survive on a wide screen');
    expect(1920 - tester.getRect(rightmost).right, closeTo(logoLeft, 6),
        reason: 'leftover width should split evenly, not collect on one side');
  });

  for (final width in [320.0, 360.0, 420.0, 560.0, 700.0, 820.0, 1024.0, 1180.0, 1280.0, 1440.0, 1600.0, 1920.0, 2560.0]) {
    testWidgets('nav lays out cleanly at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'nav overflowed at ${width}px');

      // The original defect: links rendered past the edge of the bar, so
      // "For Station Owners" showed as "For Statio" and the last three links
      // were invisible. A link is either laid out inside the bar or replaced
      // by the menu -- never half-drawn.
      final navRect = tester.getRect(find.byType(WebNavBar));
      for (final label in _navLabels) {
        final finder = find.text(label);
        if (finder.evaluate().isEmpty) continue;
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(navRect.left - 0.5), reason: '"$label" clipped at ${width}px');
        expect(rect.right, lessThanOrEqualTo(navRect.right + 0.5), reason: '"$label" clipped at ${width}px');
      }

      // Whenever the links don't fit they must be reachable some other way.
      final linksShown = find.text('Contact').evaluate().isNotEmpty;
      final menuShown = find.byIcon(Icons.menu).evaluate().isNotEmpty;
      expect(linksShown || menuShown, isTrue, reason: 'no way to navigate at ${width}px');
    });
  }
}
