import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/widgets/portal/portal_back.dart';
import 'package:aquaroute/widgets/portal/portal_page_header.dart';
import 'package:aquaroute/widgets/responsive_nav_shell.dart';

/// Back inside the portals and the customer app: the header arrow, the
/// phone's back button and the browser's Back all undo the latest step.
void main() {
  group('PortalBackController', () {
    test('section switches go back in order', () {
      final back = PortalBackController();
      var index = 0;
      void goTo(int i) {
        back.recordSection(index, (p) => index = p);
        index = i;
      }

      goTo(2);
      goTo(5);
      expect(back.depth, 2);
      expect(back.back(), isTrue);
      expect(index, 2);
      expect(back.back(), isTrue);
      expect(index, 0);
      expect(back.back(), isFalse, reason: 'nothing left: let the app close');
    });

    test('the browser going back several entries trims to that depth', () {
      final back = PortalBackController();
      var index = 0;
      for (final i in [1, 2, 3]) {
        back.recordSection(index, (p) => index = p);
        index = i;
      }
      back.trimTo(1);
      expect(index, 1);
      expect(back.depth, 1);
    });

    test('each forward step tells the website its new depth', () {
      final back = PortalBackController();
      final depths = <int>[];
      back.onForward = depths.add;
      back.recordSection(0, (_) {});
      back.recordSection(1, (_) {});
      expect(depths, [1, 2]);
    });
  });

  testWidgets('a tab switch gives the page header a back arrow that returns to the previous tab', (tester) async {
    final back = PortalBackController();
    await tester.pumpWidget(MaterialApp(
      home: PortalBackScope(
        controller: back,
        child: ResponsiveNavShell(
          backController: back,
          destinations: const [
            NavShellDestination(icon: Icons.home, label: 'Home'),
            NavShellDestination(icon: Icons.list, label: 'Orders'),
          ],
          pages: const [
            Scaffold(body: PortalPageHeader(title: 'Dashboard')),
            Scaffold(body: PortalPageHeader(title: 'Live Order Pipeline')),
          ],
        ),
      ),
    ));

    expect(find.byTooltip('Back'), findsNothing, reason: 'nowhere to go back to yet');
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('Back').hitTestable());
    await tester.pumpAndSettle();
    expect(back.canGoBack, isFalse);
    expect(find.byTooltip('Back').hitTestable(), findsNothing);
  });
}
