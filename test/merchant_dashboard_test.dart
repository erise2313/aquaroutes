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
}
