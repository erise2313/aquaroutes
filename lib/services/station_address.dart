import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/written_address.dart';

/// The water_stations columns for a station's written address: the parts,
/// the barangay link (so the directory's barangay filter finds it) and the
/// one-line `station_address` everything else already displays.
Future<Map<String, dynamic>> stationAddressPayload(
  SupabaseClient client, {
  required String street,
  required String? barangay,
  required String city,
  required String landmark,
}) async {
  String? barangayId;
  if ((barangay ?? '').isNotEmpty) {
    final row = await client.from('barangays').select('id').eq('name', barangay!).maybeSingle();
    barangayId = row?['id'] as String?;
  }
  return {
    'street': street.trim(),
    'city': city.trim().isEmpty ? kDefaultCity : city.trim(),
    'landmark': landmark.trim().isEmpty ? null : landmark.trim(),
    'barangay_id': ?barangayId,
    'station_address': formatWrittenAddress(street: street, barangay: barangay, city: city),
  };
}
