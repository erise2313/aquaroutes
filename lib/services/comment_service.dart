import '../models/bulletin_comment.dart';
import 'supabase_service.dart';

/// Comments on bulletin posts (website News page). Public read; insert
/// requires the caller to be authenticated as the commenting profile;
/// delete allowed for the comment's author or a WASA admin -- see
/// supabase/patch_bulletin_comments.sql.
class CommentService {
  CommentService(this._supabase);

  final SupabaseService _supabase;

  Future<List<BulletinComment>> fetchComments(String bulletinId) async {
    final rows = await _supabase.client
        .from('bulletin_comments')
        .select('id, bulletin_id, profile_id, body, created_at, profiles(full_name)')
        .eq('bulletin_id', bulletinId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows).map(BulletinComment.fromMap).toList();
  }

  Future<void> addComment({required String bulletinId, required String profileId, required String body}) {
    return _supabase.client.from('bulletin_comments').insert({
      'bulletin_id': bulletinId,
      'profile_id': profileId,
      'body': body,
    });
  }

  Future<void> deleteComment(String commentId) {
    return _supabase.client.from('bulletin_comments').delete().eq('id', commentId);
  }
}
