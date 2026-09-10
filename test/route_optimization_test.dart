import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aquaroute/services/route_optimization.dart';

void main() {
  const station = LatLng(14.3868, 120.8817);
  const near = LatLng(14.3880, 120.8830);
  const mid = LatLng(14.3950, 120.8700);
  const far = LatLng(14.4200, 120.9100);

  // Shape of a real route-optimize response (FOSSGIS OSRM, measured live:
  // 9.2 km, ~15 min, stops reordered).
  Map<String, dynamic> realResponse({List<int> sequence = const [1, 0]}) => {
        'provider': 'osrm',
        'sequence': sequence,
        'points': [
          [14.3868, 120.8817],
          [14.3874, 120.8822],
          [14.3880, 120.8830],
          [14.3990, 120.8950],
          [14.4200, 120.9100],
        ],
        'distance_m': 9196,
        'duration_s': 896,
      };

  group('nearestNeighbourSequence', () {
    test('visits the closest remaining stop each time', () {
      expect(nearestNeighbourSequence(station, [far, near, mid]), [1, 2, 0]);
    });

    test('handles no stops', () {
      expect(nearestNeighbourSequence(station, []), isEmpty);
    });
  });

  group('routePlanFromResponse', () {
    test('accepts a real route', () {
      final plan = routePlanFromResponse(realResponse(), 2);
      expect(plan.isApproximate, isFalse);
      expect(plan.sequence, [1, 0]);
      expect(plan.points, hasLength(5));
      expect(plan.provider, 'osrm');
      expect(plan.summary, '9.2 km · 15 min by road');
    });

    // A sequence that isn't an exact permutation would silently drop or
    // double a delivery, so it must be rejected rather than drawn.
    test('rejects a sequence that repeats a stop', () {
      expect(() => routePlanFromResponse(realResponse(sequence: [0, 0]), 2), throwsFormatException);
    });

    test('rejects a sequence that misses a stop', () {
      expect(() => routePlanFromResponse(realResponse(sequence: [0]), 2), throwsFormatException);
    });

    test('rejects an out-of-range index', () {
      expect(() => routePlanFromResponse(realResponse(sequence: [0, 2]), 2), throwsFormatException);
    });

    test('rejects missing or degenerate geometry', () {
      final noPoints = realResponse()..remove('points');
      final onePoint = realResponse()..['points'] = [
          [14.38, 120.88],
        ];
      final badPoint = realResponse()..['points'] = [
          [14.38, 120.88],
          ['x', 120.9],
        ];
      expect(() => routePlanFromResponse(noPoints, 2), throwsFormatException);
      expect(() => routePlanFromResponse(onePoint, 2), throwsFormatException);
      expect(() => routePlanFromResponse(badPoint, 2), throwsFormatException);
    });

    test('rejects an error payload', () {
      expect(() => routePlanFromResponse({'error': 'unavailable'}, 2), throwsFormatException);
      expect(() => routePlanFromResponse('nope', 2), throwsFormatException);
    });
  });

  group('planRoute', () {
    test('uses the routing service when it answers', () async {
      Map<String, dynamic>? sent;
      final service = RouteOptimizationService(invoker: (body) async {
        sent = body;
        return realResponse();
      });

      final plan = await service.planRoute(station, [far, near]);

      expect(plan.isApproximate, isFalse);
      expect(plan.sequence, [1, 0]);
      expect(sent!['origin'], {'lat': station.latitude, 'lng': station.longitude});
      expect((sent!['stops'] as List), hasLength(2));
    });

    // The bug this replaces: straight lines drawn as if they were a route.
    // The fallback must still order sensibly, draw one segment per stop,
    // and say it's approximate.
    test('falls back to a flagged straight-line estimate when the service fails', () async {
      final service = RouteOptimizationService(invoker: (_) async => throw Exception('502'));

      final plan = await service.planRoute(station, [far, near, mid]);

      expect(plan.isApproximate, isTrue);
      expect(plan.summary, isNull, reason: 'a straight-line distance would understate the drive');
      expect(plan.sequence, [1, 2, 0]);
      expect(plan.points, [station, near, mid, far]);
    });

    test('falls back when the service returns something untrustworthy', () async {
      final service = RouteOptimizationService(invoker: (_) async => realResponse(sequence: [0, 0]));

      final plan = await service.planRoute(station, [far, near]);

      expect(plan.isApproximate, isTrue);
      expect(plan.sequence.toSet(), {0, 1});
    });

    test('a real route carries road geometry, not one segment per stop', () async {
      final real = await RouteOptimizationService(invoker: (_) async => realResponse()).planRoute(station, [far, near]);
      final fallback = await RouteOptimizationService(invoker: (_) async => throw Exception()).planRoute(station, [far, near]);

      expect(fallback.points, hasLength(3)); // origin + 2 stops: straight lines
      expect(real.points.length, greaterThan(fallback.points.length));
    });

    test('with no stops, does not call the service at all', () async {
      var called = false;
      final service = RouteOptimizationService(invoker: (_) async {
        called = true;
        return realResponse();
      });

      final plan = await service.planRoute(station, []);

      expect(called, isFalse);
      expect(plan.sequence, isEmpty);
      expect(plan.isApproximate, isFalse);
    });
  });
}
