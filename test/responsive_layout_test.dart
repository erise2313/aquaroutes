import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/widgets/admin_charts.dart';
import 'package:aquaroute/widgets/portal/fill_grid.dart';

Future<void> _pump(WidgetTester tester, Widget child, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: AdminTheme.themeData,
    home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
  ));
}

void main() {
  group('FillGrid', () {
    for (final width in [320.0, 360.0, 768.0, 1280.0]) {
      testWidgets('tiles fill the row with no gap at $width px', (tester) async {
        await _pump(
          tester,
          FillGrid(children: [for (var i = 0; i < 4; i++) Container(key: ValueKey(i), height: 60, color: Colors.blue)]),
          width,
        );
        final available = width - 32;
        final first = tester.getRect(find.byKey(const ValueKey(0)));
        // The first row ends at the right edge, whatever the column count.
        final rowEnd = [for (var i = 0; i < 4; i++) tester.getRect(find.byKey(ValueKey(i)))]
            .where((r) => r.top == first.top)
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b);
        expect(rowEnd, closeTo(16 + available, 0.5));
        expect(first.width, greaterThanOrEqualTo(150));
      });
    }
  });

  group('AdminDonutChart', () {
    for (final width in [320.0, 360.0, 768.0, 1280.0]) {
      testWidgets('stays inside its card at $width px', (tester) async {
        await _pump(
          tester,
          const AdminChartCard(
            title: 'Accreditation status',
            height: null,
            child: AdminDonutChart(slices: {'Pending': 6, 'Under review': 1, 'Accredited': 2}),
          ),
          width,
        );
        expect(tester.takeException(), isNull);
        final card = tester.getRect(find.byType(Card));
        final chart = tester.getRect(find.byType(AdminDonutChart));
        expect(chart.left, greaterThanOrEqualTo(card.left));
        expect(chart.right, lessThanOrEqualTo(card.right));
        expect(find.text('Under review'), findsOneWidget);
      });
    }
  });
}
