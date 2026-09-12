import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/widgets/portal/portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// PortalEmptyState fills whole screens across the customer app and both
/// portals, and it used to be a bare Center + Column. On a phone held
/// sideways that is shorter than its own content, which overflowed by 174px
/// on the order login gate.
///
/// It also has to keep shrink-wrapping inside a ListView, where the incoming
/// height is unbounded -- wrapping it in a scroll view unconditionally would
/// assert there instead.
const _state = PortalEmptyState(
  icon: Icons.local_shipping_outlined,
  title: 'Sign in to place an order',
  message: 'Browsing the bulletin board and the station map never needs an account -- only ordering does.',
);

Future<void> _pump(WidgetTester tester, Widget child, {required Size size, double textScale = 1.0}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('PortalEmptyState', () {
    // Portrait and landscape, at the text sizes that make the content taller
    // than a sideways phone.
    for (final size in [const Size(390, 844), const Size(844, 390), const Size(640, 360)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('fills ${size.width.toInt()}x${size.height.toInt()} at ${scale}x without overflowing', (tester) async {
          await _pump(tester, _state, size: size, textScale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflowed at ${size.width}x${size.height}, text scale $scale',
          );
        });
      }
    }

    testWidgets('with an action, sideways, at large text', (tester) async {
      await _pump(
        tester,
        PortalEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Track a delivery',
          message: 'Look up a guest order with its ID and phone number, or sign in to see your order history.',
          action: PortalActionRow(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Track a guest order')),
              OutlinedButton(onPressed: () {}, child: const Text('Sign in')),
            ],
          ),
        ),
        size: const Size(844, 390),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });

    // The other half of the contract: inside a ListView the height is
    // unbounded, and it must shrink-wrap rather than try to scroll.
    testWidgets('shrink-wraps inside a ListView', (tester) async {
      await _pump(
        tester,
        ListView(children: const [SizedBox(height: 24), _state]),
        size: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Sign in to place an order'), findsOneWidget);
    });
  });
}
