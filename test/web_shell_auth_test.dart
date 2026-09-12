import 'package:aquaroute/providers/app_state.dart';
import 'package:aquaroute/web_router.dart';
import 'package:aquaroute/widgets/web_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A signed-in session, without standing up Supabase. Only `.session != null`
/// is read by isSignedInProvider, so a bare Session with the fields its
/// constructor demands is enough.
final _session = Session(
  accessToken: 'test-access-token',
  tokenType: 'bearer',
  user: const User(
    id: '00000000-0000-0000-0000-000000000001',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00.000Z',
  ),
);

// Return types are inferred rather than named: the override type Riverpod
// hands back isn't exported under a stable public name.
final _signedIn = authStateProvider.overrideWith(
  (ref) => Stream.value(AuthState(AuthChangeEvent.signedIn, _session)),
);

final _signedOut = authStateProvider.overrideWith(
  (ref) => Stream.value(const AuthState(AuthChangeEvent.signedOut, null)),
);

Widget _bar({required dynamic auth}) => ProviderScope(
      overrides: [auth],
      child: const MaterialApp(
        home: Scaffold(appBar: WebNavBar(currentPage: WebPage.home), body: SizedBox()),
      ),
    );

void main() {
  group('the nav bar reflects who is signed in', () {
    // The reported bug: a signed-in station owner browsing the site saw
    // "Login" and "Register a Station", with nothing indicating a session.
    testWidgets('signed in, it offers an account menu and the dashboard', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_bar(auth: _signedIn));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
      expect(find.text('Login'), findsNothing);
      expect(find.text('Register a Station'), findsNothing);
    });

    testWidgets('signed out, it keeps login and the register CTA', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_bar(auth: _signedOut));
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
      expect(find.text('Register a Station'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('the account menu opens account settings and offers sign out', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_bar(auth: _signedIn));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Account & password'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  // The bar measures whether its links fit from the width of the actions
  // actually rendered. The signed-in pair is a different width from Login +
  // Register, and its own comments record that guessing here is what clipped
  // "For Station Owners" and dropped the last three links.
  group('the signed-in bar still lays out cleanly', () {
    const navLabels = ['Home', 'About', 'Accreditation', 'For Owners', 'News', 'Stations', 'Contact'];

    for (final width in [320.0, 420.0, 700.0, 1024.0, 1280.0, 1600.0, 1920.0]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_bar(auth: _signedIn));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'nav overflowed at ${width}px');

        final navRect = tester.getRect(find.byType(WebNavBar));
        for (final label in navLabels) {
          final finder = find.text(label);
          if (finder.evaluate().isEmpty) continue;
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(navRect.left - 0.5), reason: '"$label" clipped at ${width}px');
          expect(rect.right, lessThanOrEqualTo(navRect.right + 0.5), reason: '"$label" clipped at ${width}px');
        }

        final linksShown = find.text('Contact').evaluate().isNotEmpty;
        final menuShown = find.byIcon(Icons.menu).evaluate().isNotEmpty;
        expect(linksShown || menuShown, isTrue, reason: 'no way to navigate at ${width}px');
      });
    }
  });

  group('WebRoutes', () {
    // The portal having its own URL is what lets `/` stay the marketing home
    // while signed in -- previously `/` was AuthGate, so pressing Home swapped
    // you into the portal with no way back.
    test('the portal has a route of its own, distinct from the home page', () {
      expect(WebRoutes.portal, '/portal');
      expect(WebRoutes.home, '/');
      expect(WebRoutes.portal, isNot(WebRoutes.home));
    });
  });
}
