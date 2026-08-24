import '../models/station.dart';
import 'supabase_service.dart';

/// Station CRUD, scoped by RLS to the signed-in owner's own station(s)
/// (supabase/migrations/0009_rls.sql). Replaces the direct
/// `Supabase.instance.client.from('water_stations')` calls scattered across
/// merchant_dashboard.dart, orders_screen.dart, etc.
class StationService {
  StationService(this._supabase);

  final SupabaseService _supabase;

  Future<Station?> fetchOwnedStation(String ownerProfileId) async {
    final row = await _supabase.client
        .from('water_stations')
        .select()
        .eq('owner_profile_id', ownerProfileId)
        .maybeSingle();
    if (row == null) return null;
    return Station.fromMap(row);
  }

  Future<void> updateStation(String stationId, Map<String, dynamic> fields) async {
    await _supabase.client.from('water_stations').update(fields).eq('id', stationId);
  }

  Future<List<PublicStation>> fetchPublicStations() async {
    final rows = await _supabase.client.from('public_stations').select();
    return rows.map((r) => PublicStation.fromMap(r)).toList();
  }
}
