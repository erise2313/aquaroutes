import 'membership.dart';

/// Mirrors the `bulletins` and `floor_prices` tables
/// (supabase/migrations/0008_bulletin.sql).
enum BulletinCategory { announcement, priceChange, event, discussion }

BulletinCategory bulletinCategoryFromString(String value) {
  switch (value) {
    case 'announcement':
      return BulletinCategory.announcement;
    case 'price_change':
      return BulletinCategory.priceChange;
    case 'event':
      return BulletinCategory.event;
    default:
      return BulletinCategory.discussion;
  }
}

String bulletinCategoryToString(BulletinCategory category) {
  switch (category) {
    case BulletinCategory.announcement:
      return 'announcement';
    case BulletinCategory.priceChange:
      return 'price_change';
    case BulletinCategory.event:
      return 'event';
    case BulletinCategory.discussion:
      return 'discussion';
  }
}

String bulletinCategoryLabel(BulletinCategory category) {
  switch (category) {
    case BulletinCategory.announcement:
      return 'Official Announcement';
    case BulletinCategory.priceChange:
      return 'Price Change';
    case BulletinCategory.event:
      return 'Community Event';
    case BulletinCategory.discussion:
      return 'General Discussion';
  }
}

class Bulletin {
  final String id;
  final BulletinCategory category;
  final String title;
  final String body;
  final bool isPinned;
  final String authorName;
  final AppRole authorRole;
  final String? authorStationName;
  final String? imageUrl;
  final DateTime createdAt;

  const Bulletin({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.isPinned,
    required this.authorName,
    required this.authorRole,
    this.authorStationName,
    this.imageUrl,
    required this.createdAt,
  });

  /// e.g. "Station Owner · Buenavista Water Refilling Station" or "WASA Admin".
  String get authorBadge {
    switch (authorRole) {
      case AppRole.wasaAdmin:
        return 'WASA Admin';
      case AppRole.stationOwner:
        return authorStationName == null ? 'Station Owner' : 'Station Owner · $authorStationName';
      case AppRole.driver:
        return authorStationName == null ? 'Driver' : 'Driver · $authorStationName';
      case AppRole.publicConsumer:
        return 'Resident';
    }
  }

  factory Bulletin.fromMap(Map<String, dynamic> map) {
    return Bulletin(
      id: map['id'] as String,
      category: bulletinCategoryFromString(map['category'] as String? ?? 'discussion'),
      title: map['title'] as String,
      body: map['body'] as String,
      isPinned: map['is_pinned'] as bool? ?? false,
      authorName: map['author_name'] as String? ?? 'GENTRI WASA',
      authorRole: appRoleFromString(map['author_role'] as String? ?? 'wasa_admin'),
      authorStationName: map['author_station_name'] as String?,
      imageUrl: map['image_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class FloorPrice {
  final String id;
  final String waterType;
  final double minPricePerJug;
  final DateTime effectiveDate;

  const FloorPrice({
    required this.id,
    required this.waterType,
    required this.minPricePerJug,
    required this.effectiveDate,
  });

  factory FloorPrice.fromMap(Map<String, dynamic> map) {
    return FloorPrice(
      id: map['id'] as String,
      waterType: map['water_type'] as String,
      minPricePerJug: (map['min_price_per_jug'] as num).toDouble(),
      effectiveDate: DateTime.parse(map['effective_date'] as String),
    );
  }
}
