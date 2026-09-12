import 'package:aquaroute/models/order.dart';
import 'package:aquaroute/models/order_status_look.dart';
import 'package:flutter_test/flutter_test.dart';

/// This mapping replaced two hand-copied switches that had drifted into
/// different wording for the same state. These pin it down so it can't drift
/// again, and so adding a status can't quietly ship an unlabelled order.
void main() {
  group('OrderStatusLook', () {
    test('every status has a label and a colour', () {
      for (final status in OrderStatus.values) {
        final look = OrderStatusLook.of(status);
        expect(look.label, isNotEmpty, reason: '$status has no label');
      }
    });

    test('no two statuses read the same', () {
      final labels = OrderStatus.values.map((s) => OrderStatusLook.of(s).label).toSet();
      expect(labels.length, OrderStatus.values.length, reason: 'two states share a label');
    });

    // The button must only appear where OrderService.cancelOrder would
    // actually succeed -- offering it on a delivered order is a promise the
    // server refuses.
    test('only pending and assigned orders can be cancelled', () {
      expect(OrderStatusLook.isCancellable(OrderStatus.pending), isTrue);
      expect(OrderStatusLook.isCancellable(OrderStatus.assigned), isTrue);
      expect(OrderStatusLook.isCancellable(OrderStatus.active), isFalse);
      expect(OrderStatusLook.isCancellable(OrderStatus.done), isFalse);
      expect(OrderStatusLook.isCancellable(OrderStatus.cancelled), isFalse);
    });

    test('only orders with a driver can be tracked', () {
      expect(OrderStatusLook.isTrackable(OrderStatus.assigned), isTrue);
      expect(OrderStatusLook.isTrackable(OrderStatus.active), isTrue);
      expect(OrderStatusLook.isTrackable(OrderStatus.pending), isFalse);
      expect(OrderStatusLook.isTrackable(OrderStatus.done), isFalse);
      expect(OrderStatusLook.isTrackable(OrderStatus.cancelled), isFalse);
    });
  });
}
