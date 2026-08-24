import 'supabase_service.dart';

/// Wraps submit_station_review(), a security-definer RPC that verifies the
/// caller has a `done` order at the station before accepting a review --
/// see supabase/patch_tier1_tier2_features.sql. Direct table writes are
/// blocked by RLS on purpose; this RPC is the only insert/update path.
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
}
