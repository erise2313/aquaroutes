/// Mirrors the `bulletin_comments` table (supabase/patch_bulletin_comments.sql).
class BulletinComment {
  final String id;
  final String bulletinId;
  final String profileId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  const BulletinComment({
    required this.id,
    required this.bulletinId,
    required this.profileId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  factory BulletinComment.fromMap(Map<String, dynamic> map) {
    return BulletinComment(
      id: map['id'] as String,
      bulletinId: map['bulletin_id'] as String,
      profileId: map['profile_id'] as String,
      authorName: (map['profiles']?['full_name'] as String?) ?? 'Resident',
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
