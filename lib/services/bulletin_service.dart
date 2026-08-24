import '../models/bulletin.dart';
import '../models/membership.dart';
import 'supabase_service.dart';

/// WASA Bulletin & Floor Price Board (supabase/migrations/0008_bulletin.sql).
/// Reads are public (no login); wasa_admin may post any category,
/// station_owner/driver may only post Community Event/General Discussion
/// (enforced by RLS, not just this allow-list -- see bulletins_member_insert
/// in 0009_rls.sql).
class BulletinService {
  BulletinService(this._supabase);

  final SupabaseService _supabase;

  Future<List<Bulletin>> fetchBulletins() async {
    final rows = await _supabase.client.from('bulletins').select().order('is_pinned', ascending: false).order('created_at', ascending: false);
    return rows.map((r) => Bulletin.fromMap(r)).toList();
  }

  Future<List<FloorPrice>> fetchFloorPrices() async {
    final rows = await _supabase.client.from('floor_prices').select().order('water_type');
    return rows.map((r) => FloorPrice.fromMap(r)).toList();
  }

  /// Which categories a role is allowed to post, for the create-post sheet's
  /// category dropdown. Empty for a guest (null role) -- the FAB shows a
  /// login/register prompt instead of the sheet in that case.
  List<BulletinCategory> allowedCategoriesFor(AppRole? role) {
    switch (role) {
      case AppRole.wasaAdmin:
        return BulletinCategory.values;
      case AppRole.stationOwner:
      case AppRole.driver:
        return const [BulletinCategory.event, BulletinCategory.discussion];
      case AppRole.publicConsumer:
      case null:
        return const [];
    }
  }

  Future<void> postBulletin({
    required String associationId,
    required BulletinCategory category,
    required String title,
    required String body,
    required String postedByProfileId,
    required String authorName,
    required AppRole authorRole,
    String? authorStationName,
    String? imageUrl,
    bool isPinned = false,
  }) {
    return _supabase.client.from('bulletins').insert({
      'association_id': associationId,
      'category': bulletinCategoryToString(category),
      'title': title,
      'body': body,
      'is_pinned': isPinned,
      'posted_by': postedByProfileId,
      'author_name': authorName,
      'author_role': appRoleToString(authorRole),
      'author_station_name': authorStationName,
      'image_url': imageUrl,
    });
  }

  Future<String> fetchDefaultAssociationId() async {
    final row = await _supabase.client.from('associations').select('id').limit(1).single();
    return row['id'] as String;
  }

  /// Upserts against the (association_id, water_type) unique constraint
  /// (0008_bulletin.sql) -- re-setting a price for a water type that
  /// already has one updates it in place instead of accumulating
  /// duplicate rows (a real bug: this used to be a plain insert).
  Future<void> setFloorPrice({
    required String associationId,
    required String waterType,
    required double minPricePerJug,
    required String setByProfileId,
  }) {
    return _supabase.client.from('floor_prices').upsert({
      'association_id': associationId,
      'water_type': waterType,
      'min_price_per_jug': minPricePerJug,
      'set_by': setByProfileId,
      'effective_date': DateTime.now().toIso8601String().split('T').first,
    }, onConflict: 'association_id,water_type');
  }

  /// Admin-only (enforced by floor_prices_admin_delete RLS, 0009_rls.sql).
  Future<void> deleteFloorPrice(String id) {
    return _supabase.client.from('floor_prices').delete().eq('id', id);
  }

  /// Admin-only (enforced by bulletins_admin_delete RLS, 0009_rls.sql).
  Future<void> deleteBulletin(String bulletinId) {
    return _supabase.client.from('bulletins').delete().eq('id', bulletinId);
  }

  /// Admin-only (enforced by bulletins_admin_update RLS, 0009_rls.sql).
  Future<void> togglePin(String bulletinId, bool isPinned) {
    return _supabase.client.from('bulletins').update({'is_pinned': isPinned}).eq('id', bulletinId);
  }

  /// Reaction counts per bulletin, keyed by bulletin id -- reads the public
  /// bulletin_reaction_counts view (0008_bulletin.sql) rather than joining
  /// per-card, since a feed screen wants all counts in one round trip.
  Future<Map<String, int>> fetchReactionCounts() async {
    final rows = await _supabase.client.from('bulletin_reaction_counts').select();
    return {for (final r in rows) r['bulletin_id'] as String: (r['reaction_count'] as num).toInt()};
  }

  /// Which bulletins the current user has reacted to -- used to render the
  /// reaction icon as filled/unfilled without a per-card query.
  Future<Set<String>> fetchMyReactions(String profileId) async {
    final rows = await _supabase.client.from('bulletin_reactions').select('bulletin_id').eq('profile_id', profileId);
    return rows.map((r) => r['bulletin_id'] as String).toSet();
  }

  Future<void> addReaction(String bulletinId, String profileId) {
    return _supabase.client.from('bulletin_reactions').insert({'bulletin_id': bulletinId, 'profile_id': profileId});
  }

  Future<void> removeReaction(String bulletinId, String profileId) {
    return _supabase.client.from('bulletin_reactions').delete().eq('bulletin_id', bulletinId).eq('profile_id', profileId);
  }
}
