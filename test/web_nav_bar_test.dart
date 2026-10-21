import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/brand_fonts.dart';
import 'package:aquaroute/providers/app_state.dart';
import 'package:aquaroute/providers/web_locale_provider.dart';
import 'package:aquaroute/web_strings.dart';
import 'package:aquaroute/widgets/web_nav_bar.dart';
import 'package:aquaroute/widgets/wasa_shield_logo.dart';

// The real brand font, so widths are the site's and not the test font's
// (every glyph a full square, about twice as wide).
Widget _harness({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(fontFamily: BrandFonts.family),
        home: const Scaffold(appBar: WebNavBar(currentPage: WebPage.home), body: SizedBox()),
      ),
    );

class _TagalogLocale extends WebLocaleNotifier {
  @override
  WebLocale build() => WebLocale.tl;
}

const _navLabels = ['Home', 'About', 'Accreditation', 'For Owners', 'News', 'Stations', 'Contact'];

void main() {
  setUpAll(() async {
    final loader = FontLoader(BrandFonts.family)
      ..addFont(rootBundle.load('assets/fonts/AtkinsonHyperlegible-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/AtkinsonHyperlegible-Bold.ttf'));
    await loader.load();
  });

  // Switching to TL used to hide every link behind the menu for signed-out
  // visitors on an ordinary laptop: the Tagalog labels ("Magparehistro ng
  // Istasyon", "Makipag-ugnayan") pushed the row past the bar's width.
  for (final tagalog in [false, true]) {
    for (final signedIn in [false, true]) {
      for (final width in [1366.0, 1440.0]) {
        final lang = tagalog ? 'TL' : 'EN';
        final who = signedIn ? 'signed in' : 'signed out';
        testWidgets('all links show at ${width.toInt()}px in $lang, $who', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(_harness(overrides: [
            isSignedInProvider.overrideWith((ref) => signedIn),
            if (tagalog) webLocaleProvider.overrideWith(_TagalogLocale.new),
          ]));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final locale = tagalog ? WebLocale.tl : WebLocale.en;
          expect(find.byIcon(Icons.menu), findsNothing, reason: 'links collapsed into the menu');
          expect(find.text(WebStrings.t(locale, 'nav_contact')), findsOneWidget);
        });
      }
    }
  }

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
