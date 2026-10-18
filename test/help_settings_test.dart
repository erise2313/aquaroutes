import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/membership.dart';
import 'package:aquaroute/screens/help/help_content.dart';
import 'package:aquaroute/widgets/account_settings_section.dart';
import 'package:aquaroute/widgets/order_step_tracker.dart';

/// Phase 6 (help, settings, order steps).
void main() {
  group('orderSteps', () {
    test('a new order: placed now, the rest to come', () {
      final steps = orderSteps({'status': 'pending', 'created_at': '2026-10-18T01:00:00Z'});
      expect(steps.map((s) => s.label), ['Placed', 'Assigned to a driver', 'Out for delivery', 'Delivered']);
      expect(steps.map((s) => s.state), [OrderStepState.current, OrderStepState.upcoming, OrderStepState.upcoming, OrderStepState.upcoming]);
    });

    test('out for delivery: earlier steps done with their times', () {
      final steps = orderSteps({
        'status': 'active',
        'created_at': '2026-10-18T01:00:00Z',
        'assigned_at': '2026-10-18T01:10:00Z',
        'out_for_delivery_at': '2026-10-18T01:20:00Z',
      });
      expect(steps.map((s) => s.state), [OrderStepState.done, OrderStepState.done, OrderStepState.current, OrderStepState.upcoming]);
      expect(steps[1].at, isNotNull);
      expect(steps[3].at, isNull);
    });

    test('delivered: every step done', () {
      final steps = orderSteps({'status': 'done', 'created_at': '2026-10-18T01:00:00Z', 'delivered_at': '2026-10-18T02:00:00Z'});
      expect(steps.every((s) => s.state == OrderStepState.done), isTrue);
    });

    test('cancelled ends after the last step it reached', () {
      final steps = orderSteps({
        'status': 'cancelled',
        'created_at': '2026-10-18T01:00:00Z',
        'assigned_at': '2026-10-18T01:10:00Z',
        'cancelled_at': '2026-10-18T01:15:00Z',
      });
      expect(steps.map((s) => s.label), ['Placed', 'Assigned to a driver', 'Cancelled']);
    });

    test('a failed delivery says so', () {
      final steps = orderSteps({'status': 'cancelled', 'created_at': '2026-10-18T01:00:00Z', 'failure_reason': 'nobody_home'});
      expect(steps.last.label, 'Delivery failed');
    });
  });

  group('mutableNotificationCategoriesFor', () {
    test('never offers official or account notices', () {
      for (final role in AppRole.values) {
        final keys = mutableNotificationCategoriesFor(role).keys;
        expect(keys, isNot(contains('account')));
        expect(keys, isNot(contains('accreditation')));
        // Only categories the database accepts (patch_help_settings.sql).
        expect(keys.every({'order', 'permit', 'worker', 'bulletin'}.contains), isTrue);
      }
    });

    test('a customer is not offered permit or worker switches', () {
      expect(mutableNotificationCategoriesFor(AppRole.publicConsumer).keys, unorderedEquals(['order', 'bulletin']));
      expect(mutableNotificationCategoriesFor(null), isEmpty);
    });
  });

  test('every role has a three-page tour and some help', () {
    for (final role in AppRole.values) {
      expect(tourPagesFor(role).length, 3, reason: role.name);
      expect(helpQuestionsFor(role), isNotEmpty, reason: role.name);
    }
  });
}
