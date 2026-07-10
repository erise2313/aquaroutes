import 'package:aquaroute/screens/merchant/merchant_profile_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildProfileUpdatePayload', () {
    test('returns trimmed values for editable profile fields', () {
      final payload = buildProfileUpdatePayload(
        fullName: '  Jane Doe  ',
        businessName: '  Aqua Station  ',
        stationAddress: '  Tanza, Cavite  ',
      );

      expect(payload, {
        'full_name': 'Jane Doe',
        'business_name': 'Aqua Station',
        'station_address': 'Tanza, Cavite',
      });
    });
  });
}
