import 'package:aquaroute/screens/merchant/merchant_profile_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildProfilePayload', () {
    test('returns trimmed values for the profiles table', () {
      final payload = buildProfilePayload(fullName: '  Jane Doe  ', phoneNumber: '  09171234567  ');

      expect(payload, {
        'full_name': 'Jane Doe',
        'phone_number': '09171234567',
      });
    });
  });

  group('buildStationPayload', () {
    test('returns trimmed values for the water_stations table', () {
      final payload = buildStationPayload(stationName: '  Aqua Station  ', stationAddress: '  Tanza, Cavite  ');

      expect(payload, {
        'station_name': 'Aqua Station',
        'station_address': 'Tanza, Cavite',
      });
    });
  });
}
