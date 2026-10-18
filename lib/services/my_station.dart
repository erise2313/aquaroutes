import 'package:supabase_flutter/supabase_flutter.dart';

/// The station the signed-in person works for, with the given [columns].
///
/// Station screens used to look it up by `owner_profile_id = me`, which only
/// works for the owner. Station staff use the same Orders, Track and Drivers
/// screens, so this goes through the person's own membership row (always
/// readable to them) and then reads the station, which RLS lets both the
/// owner and their staff see. Falls back to the owner lookup for an owner
/// whose membership has no station recorded.
Future<Map<String, dynamic>?> fetchMyStation(SupabaseClient client, {String columns = 'id'}) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;

  final membership = await client
      .from('memberships')
      .select('station_id')
      .eq('profile_id', userId)
      .inFilter('role', ['station_owner', 'station_staff'])
      .eq('status', 'active')
      .maybeSingle();
  final stationId = membership?['station_id'] as String?;

  if (stationId != null) {
    return client.from('water_stations').select(columns).eq('id', stationId).maybeSingle();
  }
  return client.from('water_stations').select(columns).eq('owner_profile_id', userId).maybeSingle();
}
