import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/widgets/delivery_panel_layout.dart';

/// Phone screens from small budget Androids up to large ones, portrait and
/// landscape, at text sizes up to double.
const _sizes = [
  Size(320, 568),
  Size(360, 640),
  Size(360, 740),
  Size(393, 851),
  Size(412, 915),
  Size(640, 360),
  Size(851, 393),
];
const _scales = [1.0, 1.3, 1.6, 2.0];

Widget _details() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Order #A1B2C3', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('Deliver to: Maria Concepcion Dela Cruz-Villanueva'),
        for (var i = 0; i < 4; i++)
          const Row(children: [
            Icon(Icons.water_drop),
            SizedBox(width: 12),
            Text('Payload'),
            SizedBox(width: 12),
            Expanded(child: Text('2 × Slim 5-gal · Purified', textAlign: TextAlign.end)),
          ]),
        OutlinedButton(onPressed: () {}, child: const Text('NAVIGATE')),
      ],
    );

Widget _actions(VoidCallback onComplete) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('START DELIVERY')),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: onComplete, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('COMPLETE DELIVERY')),
        TextButton(onPressed: () {}, child: const Text("COULDN'T DELIVER")),
      ],
    );

void main() {
  for (final size in _sizes) {
    for (final scale in _scales) {
      testWidgets('buttons stay on screen at ${size.width.toInt()}×${size.height.toInt()}, text ×$scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var completed = 0;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale), padding: const EdgeInsets.only(bottom: 24)),
            child: Scaffold(
              appBar: AppBar(title: const Text('Driver Dashboard')),
              // Like the real screen: the on-duty bar sits above the panel.
              body: Column(children: [
                const SizedBox(height: 60, child: Placeholder()),
                Expanded(
                  child: DeliveryPanelLayout(
                    map: const ColoredBox(color: Colors.blueGrey),
                    details: _details(),
                    actions: _actions(() => completed++),
                    background: Colors.white,
                  ),
                ),
              ]),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);

        // COMPLETE is on screen and tappable (on the shortest landscape
        // screens at the largest text, after a short scroll of the buttons).
        final complete = find.text('COMPLETE DELIVERY');
        await tester.ensureVisible(complete);
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.ancestor(of: complete, matching: find.byType(ElevatedButton)));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
        await tester.tap(complete);
        expect(completed, 1);

        // NAVIGATE can always be scrolled into view.
        await tester.scrollUntilVisible(find.text('NAVIGATE'), 80, scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
