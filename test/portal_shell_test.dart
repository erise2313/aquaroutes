import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/widgets/portal/portal_shell.dart';
import 'package:aquaroute/widgets/responsive_nav_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = [
  NavShellDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
  NavShellDestination(icon: Icons.list_alt, label: 'Orders', group: 'Operations'),
  NavShellDestination(icon: Icons.sell_outlined, label: 'Products', group: 'Operations'),
];

/// An admin-shaped set: three phone tabs, the rest on "More", one web-only.
const _adminLike = [
  NavShellDestination(icon: Icons.dashboard_outlined, label: 'Overview'),
  NavShellDestination(icon: Icons.verified_outlined, label: 'Stations', group: 'Compliance'),
  NavShellDestination(icon: Icons.fact_check_outlined, label: 'Permits', group: 'Compliance', phoneTab: false, badgeCount: 3),
  NavShellDestination(icon: Icons.badge_outlined, label: 'Workers', group: 'Compliance'),
  NavShellDestination(icon: Icons.event_outlined, label: 'Events', group: 'Content', phoneTab: false),
  NavShellDestination(icon: Icons.folder_open_outlined, label: 'Resources', group: 'Content', phoneTab: false),
  NavShellDestination(icon: Icons.swap_horiz, label: 'WebOnly', group: 'Content', onPhone: false),
];

Widget _host(Widget shell) => MaterialApp(theme: AppTheme.light, home: shell);

Widget _shell({bool? web, List<NavShellDestination> destinations = _destinations}) => _host(PortalShell(
      portalName: 'Test portal',
      webLayout: web,
      destinations: destinations,
      pages: [for (final d in destinations) Text('${d.label.toUpperCase()} PAGE')],
      footerActions: const [IconButton(tooltip: 'Account', onPressed: null, icon: Icon(Icons.person))],
    ));

Future<void> _size(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  group('PortalShell in the app', () {
    testWidgets('keeps the bottom tab bar and grows no sidebar', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_shell(web: false));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(PortalSidebar), findsNothing);
    });

    testWidgets('switches page when a destination is tapped', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_shell(web: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(stack.index, 1, reason: 'tapping Orders should select the second page');
    });

    testWidgets('a destination with no pending work shows no badge', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_shell(web: false));
      await tester.pumpAndSettle();

      // A badge reading "0" would be worse than none at all.
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('extra sections go on a More tab, web-only ones are left out', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_shell(web: false, destinations: _adminLike));
      await tester.pumpAndSettle();

      final bar = tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar.items.map((i) => i.label), ['Overview', 'Stations', 'Workers', 'More']);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(find.text('Permits'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Resources'), findsOneWidget);
      expect(find.text('WebOnly'), findsNothing);
      // The More page carries the account controls; without them an officer
      // in the app could not sign out.
      expect(find.byTooltip('Account'), findsOneWidget);
    });

    testWidgets('a More entry opens its page', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_shell(web: false, destinations: _adminLike));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.text('EVENTS PAGE'), findsOneWidget);
    });
  });

  group('PortalShell in a browser', () {
    testWidgets('wide: a full sidebar listing every section under its group', (tester) async {
      await _size(tester, const Size(1440, 900));
      await tester.pumpWidget(_shell(web: true, destinations: _adminLike));
      await tester.pumpAndSettle();

      expect(find.byType(PortalSidebar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      for (final d in _adminLike) {
        expect(find.text(d.label), findsOneWidget, reason: '${d.label} must be reachable from the sidebar');
      }
      expect(find.text('COMPLIANCE'), findsOneWidget);
      expect(find.text('CONTENT'), findsOneWidget);
      // Badge as a count chip next to the label.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('choosing a section shows its page', (tester) async {
      await _size(tester, const Size(1440, 900));
      await tester.pumpWidget(_shell(web: true, destinations: _adminLike));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resources'));
      await tester.pumpAndSettle();

      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack).first);
      expect(stack.index, 5);
    });

    testWidgets('medium: collapses to an icon rail with tooltips', (tester) async {
      await _size(tester, const Size(960, 800));
      await tester.pumpWidget(_shell(web: true, destinations: _adminLike));
      await tester.pumpAndSettle();

      expect(find.byType(PortalSidebar), findsOneWidget);
      expect(find.text('Resources'), findsNothing, reason: 'labels move into tooltips on the rail');
      expect(find.byTooltip('Resources'), findsOneWidget);
    });

    testWidgets('narrow: a menu button opens the sidebar as a drawer', (tester) async {
      await _size(tester, const Size(600, 900));
      await tester.pumpWidget(_shell(web: true, destinations: _adminLike));
      await tester.pumpAndSettle();

      expect(find.byType(PortalSidebar), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.byType(PortalSidebar), findsOneWidget);
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.byType(PortalSidebar), findsNothing, reason: 'the drawer closes after choosing');
      final stack = tester.widget<IndexedStack>(find.byType(IndexedStack).first);
      expect(stack.index, 4);
    });

    testWidgets('a screen opened from a section keeps the sidebar beside it', (tester) async {
      await _size(tester, const Size(1440, 900));
      await tester.pumpWidget(_host(PortalShell(
        portalName: 'Test portal',
        webLayout: true,
        destinations: _destinations,
        pages: [
          Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const Text('DETAIL PAGE')),
              ),
              child: const Text('open detail'),
            ),
          ),
          const Text('ORDERS PAGE'),
          const Text('PRODUCTS PAGE'),
        ],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open detail'));
      await tester.pumpAndSettle();

      expect(find.text('DETAIL PAGE'), findsOneWidget);
      expect(find.byType(PortalSidebar), findsOneWidget);

      // Choosing the section you're in returns to its first page.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL PAGE'), findsNothing);
      expect(find.text('open detail'), findsOneWidget);
    });
  });
}
