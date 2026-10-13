import '../models/station.dart';
import 'supabase_service.dart';

/// A customer's own shortlist of stations (`favorite_stations`, see
/// supabase/migrations/0011_favorite_stations.sql). RLS scopes every row to
/// the signed-in profile, so none of these calls filter by profile id
/// themselves -- the database does it.
///
/// Guests have no favourites rather than locally-stored ones: [fetchIds]
/// returns an empty set when signed out and the star is hidden, so there is
/// never a local list to reconcile at sign-in.
class FavoriteStationService {
  FavoriteStationService(this._supabase);

  final SupabaseService _supabase;

  bool get isSignedIn => _supabase.client.auth.currentUser != null;

  Future<Set<String>> fetchIds() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return <String>{};
    final rows = await _supabase.client.from('favorite_stations').select('station_id');
    return rows.map((r) => r['station_id'] as String).toSet();
  }

  Future<void> add(String stationId) async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return;
    // Upsert rather than insert: double-tapping the star before the first
    // round trip lands would otherwise throw on the composite primary key.
    await _supabase.client.from('favorite_stations').upsert(
      {'profile_id': userId, 'station_id': stationId},
      onConflict: 'profile_id,station_id',
    );
  }

  Future<void> remove(String stationId) async {
    if (!isSignedIn) return;
    await _supabase.client.from('favorite_stations').delete().eq('station_id', stationId);
  }

  /// Favourites first, everything else after, each group keeping the order it
  /// arrived in -- which is the distance sort when a GPS fix was available and
  /// the server's order otherwise. Deliberately a pure function so the pinning
  /// rule is testable without a client; see test/favorite_stations_test.dart.
  static List<PublicStation> pinFavorites(List<PublicStation> stations, Set<String> favoriteIds) {
    if (favoriteIds.isEmpty) return stations;
    final favorites = <PublicStation>[];
    final rest = <PublicStation>[];
    for (final station in stations) {
      (favoriteIds.contains(station.id) ? favorites : rest).add(station);
    }
    return [...favorites, ...rest];
  }
}
