import 'supabase_service.dart';

/// Station reviews: customers write them, station owners read the ones about
/// their station, officers moderate.
///
/// Writing goes through submit_station_review(), a security-definer RPC that
/// verifies the caller has a `done` order at the station before accepting a
/// review -- see supabase/patch_tier1_tier2_features.sql. Direct table writes
/// are blocked by RLS on purpose; this RPC is the only insert/update path.
/// Reviews are publicly readable (reviews_public_read); only officers can
/// delete one (reviews_admin_all).
class ReviewService {
  ReviewService(this._supabase);

  final SupabaseService _supabase;

  Future<void> submitReview({required String stationId, required int rating, String? comment}) {
    return _supabase.client.rpc('submit_station_review', params: {
      'p_station_id': stationId,
      'p_rating': rating,
      'p_comment': comment,
    });
  }

  /// The reviews of one station, newest first. Reviewers' names are not
  /// included: profiles are private to their owner and to officers.
  Future<List<Map<String, dynamic>>> fetchStationReviews(String stationId) async {
    final rows = await _supabase.client
        .from('reviews')
        .select('id, rating, comment, created_at')
        .eq('station_id', stationId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Every review in the association, with its station and reviewer, for
  /// officers.
  Future<List<Map<String, dynamic>>> fetchAllReviews() async {
    final rows = await _supabase.client
        .from('reviews')
        .select('id, rating, comment, created_at, station_id, water_stations(station_name), profiles(full_name)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Officers only (enforced by RLS). The station's average rating is
  /// computed live (public_stations), so it updates at once.
  Future<void> deleteReview(String reviewId) {
    return _supabase.client.from('reviews').delete().eq('id', reviewId);
  }
}
