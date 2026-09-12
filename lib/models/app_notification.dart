/// One row of the in-app inbox -- mirrors `notifications`
/// (supabase/patch_notifications.sql). Written only by database triggers,
/// so the wording is identical for every client.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    this.body,
    this.orderId,
    this.stationId,
    required this.isRead,
    required this.createdAt,
  });

  final String id;

  /// 'order', 'permit', 'accreditation' or 'account'.
  final String category;
  final String title;
  final String? body;
  final String? orderId;
  final String? stationId;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      category: map['category'] as String? ?? 'order',
      title: map['title'] as String? ?? 'Update',
      body: map['body'] as String?,
      orderId: map['order_id'] as String?,
      stationId: map['station_id'] as String?,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// "just now" / "5m ago" / "3h ago" / "2d ago", then a plain date. Kept
/// top-level so it can be tested without pumping a widget.
String notificationAge(DateTime createdAt, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(createdAt);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
}
