import '../models/event.dart';
import 'supabase_service.dart';

/// Association events (general assemblies, seminars). Public read; writes
/// restricted to WASA admins by the events_admin_all RLS policy -- see
/// supabase/patch_tier1_tier2_features.sql.
class EventService {
  EventService(this._supabase);

  final SupabaseService _supabase;

  Future<List<AssociationEvent>> fetchEvents() async {
    final rows = await _supabase.client.from('events').select().order('event_date', ascending: true);
    return List<Map<String, dynamic>>.from(rows).map(AssociationEvent.fromMap).toList();
  }

  Future<void> createEvent({
    required String title,
    String? description,
    required DateTime eventDate,
    String? location,
  }) async {
    final userId = _supabase.client.auth.currentUser!.id;
    await _supabase.client.from('events').insert({
      'title': title,
      'description': description,
      'event_date': eventDate.toIso8601String(),
      'location': location,
      'created_by': userId,
    });
  }

  /// Editing an event previously wasn't possible at all -- a typo in a title
  /// or a rescheduled assembly meant deleting and re-creating it, which loses
  /// the row (and its id) from anything referencing it.
  Future<void> updateEvent({
    required String eventId,
    required String title,
    String? description,
    required DateTime eventDate,
    String? location,
  }) {
    return _supabase.client.from('events').update({
      'title': title,
      'description': description,
      'event_date': eventDate.toIso8601String(),
      'location': location,
    }).eq('id', eventId);
  }

  Future<void> deleteEvent(String eventId) {
    return _supabase.client.from('events').delete().eq('id', eventId);
  }
}
