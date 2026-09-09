import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/services/admin_analytics_service.dart';
import 'package:aquaroute/widgets/admin_charts.dart';
import 'package:aquaroute/widgets/admin_filter_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AdminTheme.themeData,
      home: Scaffold(body: child),
    );

void main() {
  group('AdminFilterBar', () {
    Widget bar(TextEditingController c, {String? summary}) => AdminFilterBar(
          searchHint: 'Search by station name or address',
          searchController: c,
          onSearchChanged: (_) {},
          resultSummary: summary,
          filters: [
            AdminFilterGroup(
              label: 'Show',
              options: const {null: 'All', 'accredited': 'Accredited', 'pending': 'Pending Review', 'deactivated': 'Deactivated'},
              selected: null,
              onChanged: (_) {},
            ),
          ],
        );

    // The admin portal now runs from a phone up to a 1440px column, and the
    // chip row is the widest thing on these screens.
    for (final width in [360.0, 600.0, 800.0, 1100.0, 1440.0]) {
      testWidgets('lays out without overflow at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_wrap(bar(controller, summary: '3 of 48 stations')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'filter bar overflowed at ${width}px');
      });
    }

    testWidgets('shows a clear button only once something is typed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(bar(controller)));
      expect(find.byTooltip('Clear search'), findsNothing);

      controller.text = 'aqua';
      await tester.pumpWidget(_wrap(bar(controller)));
      expect(find.byTooltip('Clear search'), findsOneWidget);
    });
  });

  group('AdminChartCard', () {
    // An empty chart with axes and no bars looks like a rendering failure.
    // The card must show the explanation instead of the chart.
    testWidgets('renders the empty message instead of the chart when empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdminChartCard(
          title: 'Permit expiry runway',
          isEmpty: true,
          emptyMessage: 'No expiry dates recorded.',
          child: Text('CHART BODY'),
        ),
      ));
      expect(find.text('No expiry dates recorded.'), findsOneWidget);
      expect(find.text('CHART BODY'), findsNothing);
    });

    testWidgets('renders the chart and a footnote when it has data', (tester) async {
      await tester.pumpWidget(_wrap(
        const AdminChartCard(
          title: 'Newly accredited stations',
          footnote: '2 station(s) accredited before this was tracked are not shown.',
          child: Text('CHART BODY'),
        ),
      ));
      expect(find.text('CHART BODY'), findsOneWidget);
      expect(find.textContaining('not shown'), findsOneWidget);
    });
  });

  group('AdminMonthBarChart', () {
    testWidgets('renders an all-zero series without collapsing or throwing', (tester) async {
      final buckets = bucketByMonth(const <DateTime>[], monthsBack: 6, now: DateTime(2026, 9, 15));
      await tester.pumpWidget(_wrap(SizedBox(height: 220, child: AdminMonthBarChart(buckets: buckets))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a populated series', (tester) async {
      final buckets = bucketByMonth(
        [DateTime(2026, 8, 4), DateTime(2026, 9, 1), DateTime(2026, 9, 20)],
        monthsBack: 6,
        now: DateTime(2026, 9, 15),
      );
      await tester.pumpWidget(_wrap(SizedBox(height: 220, child: AdminMonthBarChart(buckets: buckets))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sep'), findsOneWidget);
    });
  });

  group('AdminDonutChart', () {
    testWidgets('lists each slice with its count and skips empty ones', (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(height: 220, child: AdminDonutChart(slices: {'Accredited': 2, 'Pending': 3, 'Rejected': 0})),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Accredited'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      // A zero slice would render an invisible wedge and a misleading legend row.
      expect(find.text('Rejected'), findsNothing);
    });
  });
}
