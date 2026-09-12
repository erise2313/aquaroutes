import 'package:aquaroute/widgets/brand_top_bar.dart';
import 'package:aquaroute/widgets/portal/portal_shell.dart';
import 'package:aquaroute/widgets/responsive_nav_shell.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `kIsWeb` is a compile-time constant and false under `flutter test`, so
/// these exercise the shell's mobile branch -- which is the branch that had
/// to stay exactly as the app has always had it. The web branch (brand bar,
/// section links, no rail) is a browser check; the pieces it is built from
/// are covered on their own in web_nav_bar_test and web_shell_auth_test.
const _destinations = [
  NavShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
  NavShellDestination(icon: Icons.list_alt, label: 'Orders'),
  NavShellDestination(icon: Icons.sell_outlined, label: 'Products'),
];

var _brandTaps = 0;

Widget _shell() => MaterialApp(
      home: PortalShell(
        destinations: _destinations,
        pages: const [Text('HOME PAGE'), Text('ORDERS PAGE'), Text('PRODUCTS PAGE')],
        onBrandTap: () => _brandTaps++,
        background: const Color(0xFFF7F5F0),
        foreground: const Color(0xFF0B2545),
        borderColor: const Color(0xFFE3DFD3),
        activeColor: const Color(0xFF1565C0),
        underlineColor: const Color(0xFFC99A3B),
        actionsWidth: 100,
        actionsBuilder: (context, layout) => const [SizedBox(width: 44, height: 44)],
      ),
    );

void main() {
  setUp(() => _brandTaps = 0);

  group('PortalShell on the mobile app', () {
    testWidgets('keeps the bottom tab bar and grows no top bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      expect(kIsWeb, isFalse, reason: 'these assertions describe the app branch');
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      // The app has never had a brand bar taking a fifth of a phone screen,
      // and this change was not supposed to give it one.
      expect(find.byType(BrandTopBar), findsNothing);
    });

    testWidgets('switches page when a destination is tapped', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      // IndexedStack keeps every page mounted, so "showing" is about which
      // one is visible rather than which exists.
      expect(find.text('HOME PAGE'), findsOneWidget);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, 1, reason: 'tapping Orders should select the second page');
    });

    testWidgets('a destination carrying a badge count shows one', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PortalShell(
          destinations: const [
            NavShellDestination(icon: Icons.home_outlined, label: 'Home'),
            NavShellDestination(icon: Icons.list_alt, label: 'Orders', badgeCount: 4),
          ],
          pages: const [Text('A'), Text('B')],
          onBrandTap: () {},
          background: const Color(0xFFF7F5F0),
          foreground: const Color(0xFF0B2545),
          borderColor: const Color(0xFFE3DFD3),
          activeColor: const Color(0xFF1565C0),
          underlineColor: const Color(0xFFC99A3B),
          actionsWidth: 100,
          actionsBuilder: (context, layout) => const [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a destination with no pending work shows no badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_shell());
      await tester.pumpAndSettle();

      // A badge reading "0" would be worse than none at all.
      expect(find.byType(Badge), findsNothing);
    });
  });
}
