import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/widgets/portal/portal_shell.dart';
import 'package:aquaroute/widgets/responsive_nav_shell.dart';

/// The light/dark switch in the sidebar has to reach the page beside it.
///
/// Each section's page used to be wrapped in a copy of the Theme taken when
/// the section first opened. Toggling then changed the sidebar but not the
/// page, and a station owner saw a light sidebar next to a dark dashboard.
void main() {
  testWidgets('toggling the theme reaches a page that is already open', (tester) async {
    var brightness = Brightness.light;
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        setOuter = setState;
        return Theme(
          data: ThemeData(brightness: brightness),
          child: PortalShell(
            webLayout: true,
            portalName: 'Station portal',
            destinations: const [NavShellDestination(icon: Icons.home_outlined, label: 'Home')],
            pages: [
              Builder(builder: (context) => Text('page:${Theme.of(context).brightness.name}')),
            ],
          ),
        );
      }),
    ));

    expect(find.text('page:light'), findsOneWidget);

    setOuter(() => brightness = Brightness.dark);
    await tester.pumpAndSettle();

    expect(find.text('page:dark'), findsOneWidget);
  });

  testWidgets('pages can tell when the sidebar already carries the controls', (tester) async {
    bool? insideShell;
    await tester.pumpWidget(MaterialApp(
      home: PortalShell(
        webLayout: true,
        portalName: 'Station portal',
        destinations: const [NavShellDestination(icon: Icons.home_outlined, label: 'Home')],
        pages: [
          Builder(builder: (context) {
            insideShell = PortalShellScope.isPresent(context);
            return const SizedBox();
          }),
        ],
      ),
    ));
    expect(insideShell, isTrue);

    bool? outside;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        outside = PortalShellScope.isPresent(context);
        return const SizedBox();
      }),
    ));
    expect(outside, isFalse);
  });
}
