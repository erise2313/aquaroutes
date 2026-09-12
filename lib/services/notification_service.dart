import '../models/app_notification.dart';
import 'supabase_service.dart';

/// The in-app inbox (supabase/patch_notifications.sql).
///
/// Rows are written by database triggers, never by a client: there is no
/// insert policy on `notifications`. RLS limits every read and update to
/// the signed-in person's own rows, and that applies to the Realtime
/// stream too, so [watch] can't leak anyone else's.
class NotificationService {
  NotificationService(this._supabase);

  final SupabaseService _supabase;

  /// Live list, newest first. Empty when signed out.
  Stream<List<AppNotification>> watch({int limit = 50}) {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);
    return _supabase.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('profile_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(AppNotification.fromMap).toList());
  }

  Future<List<AppNotification>> fetch({int limit = 50}) async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _supabase.client
        .from('notifications')
        .select()
        .eq('profile_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<void> markRead(String id) {
    return _supabase.client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase.client
        .from('notifications')
        .update({'is_read': true})
        .eq('profile_id', userId)
        .eq('is_read', false);
  }
}
