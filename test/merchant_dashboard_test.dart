import 'package:aquaroute/screens/merchant/merchant_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateOrderCounts', () {
    test('counts pending, active (incl. assigned), and done orders from a mixed list', () {
      final orders = [
        {'status': 'pending'},
        {'status': 'assigned'},
        {'status': 'active'},
        {'status': 'done'},
        {'status': 'done'},
      ];

      final counts = calculateOrderCounts(orders);

      expect(counts['pending'], 1);
      expect(counts['active'], 2);
      expect(counts['done'], 2);
    });

    test('excludes cancelled orders from every bucket', () {
      final orders = [
        {'status': 'pending'},
        {'status': 'cancelled'},
        {'status': 'cancelled'},
      ];

      final counts = calculateOrderCounts(orders);

      expect(counts['pending'], 1);
      expect(counts['active'], 0);
      expect(counts['done'], 0);
    });
  });

  group('calculateSalesTotals', () {
    // Saturday 12 September 2026, so the Monday-start week began on the 7th.
    final now = DateTime(2026, 9, 12, 18, 0);

    test('buckets delivered orders into today, this week and this month', () {
      final totals = calculateSalesTotals([
        {'status': 'done', 'total_amount': 100, 'created_at': '2026-09-12T09:00:00'},
        {'status': 'done', 'total_amount': 50, 'created_at': '2026-09-11T09:00:00'},
        {'status': 'done', 'total_amount': 25, 'created_at': '2026-09-01T09:00:00'},
        {'status': 'done', 'total_amount': 999, 'created_at': '2026-08-20T09:00:00'},
      ], now: now);

      expect(totals.today, 100);
      expect(totals.week, 150);
      expect(totals.month, 175);
      expect(totals.deliveredToday, 1);
    });

    test('only delivered orders count as takings', () {
      final totals = calculateSalesTotals([
        {'status': 'pending', 'total_amount': 100, 'created_at': '2026-09-12T09:00:00'},
        {'status': 'active', 'total_amount': 100, 'created_at': '2026-09-12T09:00:00'},
        {'status': 'cancelled', 'total_amount': 100, 'created_at': '2026-09-12T09:00:00'},
      ], now: now);

      expect(totals.today, 0);
      expect(totals.month, 0);
      expect(totals.deliveredToday, 0);
    });

    test('survives rows with no amount or no date', () {
      final totals = calculateSalesTotals([
        {'status': 'done', 'created_at': '2026-09-12T09:00:00'},
        {'status': 'done', 'total_amount': 40},
      ], now: now);

      expect(totals.today, 0);
      expect(totals.deliveredToday, 1);
    });

    test('an empty list is zero, not a crash', () {
      final totals = calculateSalesTotals(const [], now: now);
      expect(totals.today, 0);
      expect(totals.week, 0);
      expect(totals.month, 0);
    });
  });
}
