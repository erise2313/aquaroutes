/// Mirrors the `water_stations` table (supabase/migrations/0002_stations.sql).
class Station {
  final String id;
  final String associationId;
  final String ownerProfileId;
  final String? barangayId;
  final String inviteCode;
  final String stationName;
  final String stationAddress;
  final double latitude;
  final double longitude;
  final double pricePerJug;
  final double deliveryFee;
  final List<String> offeredWaterTypes;
  final String? photoUrl;
  final bool isColorumVerified;
  final bool isAccredited;
  final String accreditationStatus;

  const Station({
    required this.id,
    required this.associationId,
    required this.ownerProfileId,
    this.barangayId,
    required this.inviteCode,
    required this.stationName,
    required this.stationAddress,
    required this.latitude,
    required this.longitude,
    required this.pricePerJug,
    required this.deliveryFee,
    required this.offeredWaterTypes,
    this.photoUrl,
    required this.isColorumVerified,
    required this.isAccredited,
    required this.accreditationStatus,
  });

  bool get offersAlkaline => offeredWaterTypes.contains('alkaline');

  factory Station.fromMap(Map<String, dynamic> map) {
    return Station(
      id: map['id'] as String,
      associationId: map['association_id'] as String,
      ownerProfileId: map['owner_profile_id'] as String,
      barangayId: map['barangay_id'] as String?,
      inviteCode: map['invite_code'] as String,
      stationName: map['station_name'] as String,
      stationAddress: map['station_address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      pricePerJug: (map['price_per_jug'] as num).toDouble(),
      deliveryFee: (map['delivery_fee'] as num).toDouble(),
      offeredWaterTypes: List<String>.from(map['offered_water_types'] as List? ?? const []),
      photoUrl: map['photo_url'] as String?,
      isColorumVerified: map['is_colorum_verified'] as bool? ?? false,
      isAccredited: map['is_accredited'] as bool? ?? false,
      accreditationStatus: map['accreditation_status'] as String? ?? 'pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'association_id': associationId,
      'owner_profile_id': ownerProfileId,
      'barangay_id': barangayId,
      'invite_code': inviteCode,
      'station_name': stationName,
      'station_address': stationAddress,
      'latitude': latitude,
      'longitude': longitude,
      'price_per_jug': pricePerJug,
      'delivery_fee': deliveryFee,
      'offered_water_types': offeredWaterTypes,
      'is_colorum_verified': isColorumVerified,
      'is_accredited': isAccredited,
      'accreditation_status': accreditationStatus,
    };
  }
}

/// Mirrors the `public_stations` view (0009_rls.sql) -- the columns exposed
/// to anonymous/public-consumer callers, with no owner PII.
class PublicStation {
  final String id;
  final String stationName;
  final String stationAddress;
  final double latitude;
  final double longitude;
  final double pricePerJug;
  final double deliveryFee;
  final List<String> offeredWaterTypes;
  final String? photoUrl;
  final bool isColorumVerified;
  final bool isAccredited;
  final String? barangayName;
  final double avgRating;
  final int reviewCount;

  const PublicStation({
    required this.id,
    required this.stationName,
    required this.stationAddress,
    required this.latitude,
    required this.longitude,
    required this.pricePerJug,
    required this.deliveryFee,
    required this.offeredWaterTypes,
    this.photoUrl,
    required this.isColorumVerified,
    required this.isAccredited,
    this.barangayName,
    this.avgRating = 0,
    this.reviewCount = 0,
  });

  bool get offersAlkaline => offeredWaterTypes.contains('alkaline');

  factory PublicStation.fromMap(Map<String, dynamic> map) {
    return PublicStation(
      id: map['id'] as String,
      stationName: map['station_name'] as String,
      stationAddress: map['station_address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      pricePerJug: (map['price_per_jug'] as num).toDouble(),
      deliveryFee: (map['delivery_fee'] as num).toDouble(),
      offeredWaterTypes: List<String>.from(map['offered_water_types'] as List? ?? const []),
      photoUrl: map['photo_url'] as String?,
      isColorumVerified: map['is_colorum_verified'] as bool? ?? false,
      isAccredited: map['is_accredited'] as bool? ?? false,
      barangayName: map['barangay_name'] as String?,
      avgRating: (map['avg_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
    );
  }
}
