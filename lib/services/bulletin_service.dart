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

  /// Which categories a role is allowed to post.
  ///
  /// Two things read this, not one: the create-post sheet's category
  /// dropdown, and whether the board's New Post button is rendered at all
  /// (screens/public/bulletin_feed.dart). An empty answer means the role
  /// cannot post, so a signed-in customer never sees the button -- change
  /// this list and you change who sees it. A guest (null role) is the one
  /// exception: the button stays as their login/register entry point.
  List<BulletinCategory> allowedCategoriesFor(AppRole? role) {
    switch (role) {
      case AppRole.wasaAdmin:
      case AppRole.wasaSuperadmin:
        return BulletinCategory.values;
      case AppRole.stationOwner:
      case AppRole.driver:
        return const [BulletinCategory.event, BulletinCategory.discussion];
      // Staff read the board; posting for the station is the owner's.
      case AppRole.stationStaff:
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

  /// Upserts against the (association_id, water_type, container_code) unique
  /// constraint (supabase/patch_product_catalog.sql) -- re-setting the floor
  /// for a water type and container that already has one updates it in
  /// place instead of accumulating duplicate rows. Floors apply to refills
  /// only.
  Future<void> setFloorPrice({
    required String associationId,
    required String waterType,
    required String containerCode,
    required double minPricePerJug,
    required String setByProfileId,
  }) {
    return _supabase.client.from('floor_prices').upsert({
      'association_id': associationId,
      'water_type': waterType,
      'container_code': containerCode,
      'min_price_per_jug': minPricePerJug,
      'set_by': setByProfileId,
      'effective_date': DateTime.now().toIso8601String().split('T').first,
    }, onConflict: 'association_id,water_type,container_code');
  }

  /// Admin-only (enforced by floor_prices_admin_delete RLS, 0009_rls.sql).
  Future<void> deleteFloorPrice(String id) {
    return _supabase.client.from('floor_prices').delete().eq('id', id);
  }

  /// Admin-only (enforced by bulletins_admin_delete RLS, 0009_rls.sql).
  Future<void> deleteBulletin(String bulletinId) {
    return _supabase.client.from('bulletins').delete().eq('id', bulletinId);
  }

  /// Admin-only (bulletins_admin_update): correct a post after publishing.
  Future<void> updateBulletin(String bulletinId, {required String title, required String body}) {
    return _supabase.client.from('bulletins').update({'title': title, 'body': body}).eq('id', bulletinId);
  }

  /// Admin-only (enforced by bulletins_admin_update RLS, 0009_rls.sql).
  Future<void> togglePin(String bulletinId, bool isPinned) {
    return _supabase.client.from('bulletins').update({'is_pinned': isPinned}).eq('id', bulletinId);
  }

  /// Any signed-in member: flag a post for an officer to look at. One report
  /// per person per post (bulletin_reports' unique key).
  Future<void> reportBulletin(String bulletinId, String reason) {
    return _supabase.client.from('bulletin_reports').insert({
      'bulletin_id': bulletinId,
      'reported_by': _supabase.client.auth.currentUser!.id,
      'reason': reason,
    });
  }

  /// Officers only (bulletins_admin_update): hide a post from every feed, or
  /// bring it back. Hiding keeps the post for the record, unlike deleting.
  Future<void> setHidden(String bulletinId, bool hidden) {
    return _supabase.client.from('bulletins').update({
      'is_hidden': hidden,
      'hidden_by': hidden ? _supabase.client.auth.currentUser?.id : null,
      'hidden_at': hidden ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', bulletinId);
  }

  /// Officers only: unresolved reports, newest first, with the post they're
  /// about.
  Future<List<Map<String, dynamic>>> fetchOpenReports() async {
    final rows = await _supabase.client
        .from('bulletin_reports')
        .select('id, reason, created_at, bulletin_id, bulletins(id, title, body, author_name, is_hidden), profiles!bulletin_reports_reported_by_fkey(full_name)')
        .isFilter('resolved_at', null)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Officers only: close every open report on a post once it's been dealt
  /// with (hidden, or judged fine).
  Future<void> resolveReports(String bulletinId) {
    return _supabase.client
        .from('bulletin_reports')
        .update({
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
          'resolved_by': _supabase.client.auth.currentUser?.id,
        })
        .eq('bulletin_id', bulletinId)
        .isFilter('resolved_at', null);
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
