import 'package:supabase_flutter/supabase_flutter.dart';

/// Fills in `row['water_stations']['station_name']` for order rows.
///
/// Customers can't read the water_stations table (it holds each station's
/// invite and staff codes), so a `water_stations(station_name)` embed came
/// back empty for them and their orders showed "Unknown Station". The names
/// come from station_names() instead, which returns names only.
Future<void> attachStationNames(SupabaseClient client, List<Map<String, dynamic>> rows) async {
  final ids = {for (final r in rows) if (r['station_id'] != null) r['station_id'] as String}.toList();
  if (ids.isEmpty) return;
  final result = await client.rpc('station_names', params: {'p_ids': ids});
  final names = {for (final r in result as List) (r as Map)['id'] as String: r['station_name'] as String?};
  for (final row in rows) {
    final name = names[row['station_id']];
    if (name != null) row['water_stations'] = {'station_name': name};
  }
}
