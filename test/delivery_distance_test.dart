import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/utils/delivery_distance.dart';

/// The "far from the drop-off" check before a driver completes a delivery.
void main() {
  test('no question near the pin', () {
    expect(farFromDropOffWarning(0), isNull);
    expect(farFromDropOffWarning(200), isNull);
  });

  test('asks when far, with the distance in words', () {
    expect(farFromDropOffWarning(350), contains('350 m'));
    expect(farFromDropOffWarning(1430), contains('1.4 km'));
  });

  test('never asks when the position is unknown (lost signal)', () {
    expect(farFromDropOffWarning(null), isNull);
  });
}
