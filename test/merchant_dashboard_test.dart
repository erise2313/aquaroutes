import 'package:aquaroute/screens/merchant/merchant_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateOrderCounts', () {
    test('counts pending, active, and completed orders from a mixed list', () {
      final orders = [
        {'status': 'pending'},
        {'status': 'active'},
        {'status': 'active'},
        {'status': 'completed'},
        {'status': 'done'},
      ];

      final counts = calculateOrderCounts(orders);

      expect(counts['pending'], 1);
      expect(counts['active'], 2);
      expect(counts['done'], 2);
    });
  });
}
