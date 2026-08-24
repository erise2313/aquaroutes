/// Mirrors the `events` table (supabase/patch_tier1_tier2_features.sql).
class AssociationEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime eventDate;
  final String? location;
  final DateTime createdAt;

  const AssociationEvent({
    required this.id,
    required this.title,
    this.description,
    required this.eventDate,
    this.location,
    required this.createdAt,
  });

  bool get isPast => eventDate.isBefore(DateTime.now());

  factory AssociationEvent.fromMap(Map<String, dynamic> map) {
    return AssociationEvent(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      eventDate: DateTime.parse(map['event_date'] as String),
      location: map['location'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
