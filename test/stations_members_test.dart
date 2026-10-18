import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/jug_ledger.dart';
import 'package:aquaroute/models/permit.dart';
import 'package:aquaroute/screens/merchant/cost_calculator_screen.dart';
import 'package:aquaroute/screens/merchant/station_new_order_dialog.dart';
import 'package:aquaroute/screens/public/customer_home_screen.dart';
import 'package:aquaroute/widgets/station_share_card.dart';

/// Phase 5 (stations, suki, new members): the station's own orders, the
/// customer's usual station, the permit checklist, the cost calculator and
/// jug disputes.
void main() {
  group('stationOrderTotal', () {
    test('a phone order delivered pays the delivery fee', () {
      final t = stationOrderTotal(unitPrice: 25, quantity: 3, deliveryFee: 10, channel: StationOrderChannel.phone, pickup: false);
      expect((t.subtotal, t.fee, t.total), (75, 10, 85));
    });

    test('pickup and walk-in pay no delivery fee', () {
      expect(stationOrderTotal(unitPrice: 25, quantity: 2, deliveryFee: 10, channel: StationOrderChannel.phone, pickup: true).total, 50);
      expect(stationOrderTotal(unitPrice: 25, quantity: 2, deliveryFee: 10, channel: StationOrderChannel.walkIn, pickup: false).total, 50);
    });
  });

  group('pickMyStationOrder', () {
    Map<String, dynamic> order(String station, String at, {String status = 'done', String? product = 'p'}) =>
        {'station_id': station, 'created_at': at, 'status': status, 'product_id': product};

    test('nothing before a first delivery', () {
      expect(pickMyStationOrder([]), isNull);
      expect(pickMyStationOrder([order('a', '2026-10-01', status: 'pending')]), isNull);
    });

    test('the station with the most deliveries, and its latest order', () {
      final picked = pickMyStationOrder([
        order('a', '2026-10-01'),
        order('b', '2026-10-10'),
        order('a', '2026-10-05'),
        order('a', '2026-09-01', status: 'cancelled'),
      ]);
      expect(picked!['station_id'], 'a');
      expect(picked['created_at'], '2026-10-05');
    });

    test('a tie goes to the more recent station', () {
      final picked = pickMyStationOrder([order('a', '2026-10-01'), order('b', '2026-10-09')]);
      expect(picked!['station_id'], 'b');
    });

    test('orders without a product (old ones) are skipped', () {
      expect(pickMyStationOrder([order('a', '2026-10-01', product: null)]), isNull);
    });
  });

  group('costPerRefill', () {
    test('spreads monthly costs over the refills and adds supplies', () {
      final c = costPerRefill(monthly: {'rent': 8000, 'power': 4000}, suppliesPerRefill: 1.5, refillsPerMonth: 1200);
      expect(c, closeTo(11.5, 0.0001));
    });

    test('needs a refill count', () {
      expect(costPerRefill(monthly: {'rent': 8000}, suppliesPerRefill: 0, refillsPerMonth: 0), isNull);
    });
  });

  group('Permit.isDone', () {
    Permit permit(String status, {DateTime? expiry}) => Permit.fromMap({
          'id': 'x',
          'station_id': 's',
          'permit_type': 'sanitary_permit',
          'status': status,
          'expiry_date': expiry?.toIso8601String(),
        });

    test('approved and current counts; expired, pending or missing do not', () {
      final today = DateTime.now();
      expect(permit('approved').isDone, isTrue);
      expect(permit('approved', expiry: today.add(const Duration(days: 30))).isDone, isTrue);
      expect(permit('approved', expiry: DateTime(today.year, today.month, today.day)).isDone, isTrue);
      expect(permit('approved', expiry: today.subtract(const Duration(days: 2))).isDone, isFalse);
      expect(permit('pending_review').isDone, isFalse);
      expect(permit('missing').isDone, isFalse);
    });
  });

  group('JugSettlement disputes', () {
    Map<String, dynamic> row({String? disputedAt, String? resolution}) => {
          'id': 'x',
          'holder_station_id': 'a',
          'owner_station_id': 'b',
          'jug_type': 'slim_5gal',
          'quantity': 10,
          'status': 'confirmed',
          'dispute_reason': disputedAt == null ? null : 'Count was off',
          'disputed_at': disputedAt,
          'dispute_resolution': resolution,
        };

    test('open until WASA decides', () {
      expect(JugSettlement.fromMap(row()).isDisputeOpen, isFalse);
      expect(JugSettlement.fromMap(row(disputedAt: '2026-10-18T00:00:00Z')).isDisputeOpen, isTrue);
      expect(JugSettlement.fromMap(row(disputedAt: '2026-10-18T00:00:00Z', resolution: 'Agreed at 10')).isDisputeOpen, isFalse);
    });
  });

  test('a station QR code links to its public page', () {
    expect(stationPublicLink('abc'), 'https://gentri-wasa.web.app/stations/abc');
  });
}
