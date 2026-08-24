/// Mirrors the `resources` table (supabase/patch_tier1_tier2_features.sql).
class Resource {
  final String id;
  final String title;
  final String category;
  final String storagePath;
  final String fileUrl;
  final DateTime createdAt;

  const Resource({
    required this.id,
    required this.title,
    required this.category,
    required this.storagePath,
    required this.fileUrl,
    required this.createdAt,
  });

  factory Resource.fromMap(Map<String, dynamic> map) {
    return Resource(
      id: map['id'] as String,
      title: map['title'] as String,
      category: map['category'] as String? ?? 'general',
      storagePath: map['storage_path'] as String,
      fileUrl: map['file_url'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
