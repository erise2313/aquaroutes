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
  final bool isActive;
  final List<String> offeredJugTypes;
  final bool offersJugExchange;
  final bool acceptsNewOrders;
  final List<int>? operatingDays;
  final String? opensAt;
  final String? closesAt;

  /// Whether a customer can actually order from this station right now --
  /// requires the WASA-admin-controlled `isActive` (not suspended), the
  /// owner's own `acceptsNewOrders` toggle ("open right now"), AND being
  /// within the owner's declared operating hours if they've set any.
  /// Deliberately separate flags (see supabase/patch_station_discovery.sql,
  /// supabase/patch_jug_type_and_hours.sql) so an owner's own open/closed
  /// toggle can never undo an admin suspension, and a schedule is purely
  /// additive -- a station that never sets hours behaves exactly as before.
  bool get isOrderable => isActive && acceptsNewOrders && isOpenNow;

  bool get isOpenNow => stationIsOpenNow(operatingDays: operatingDays, opensAt: opensAt, closesAt: closesAt);

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
    this.isActive = true,
    this.offeredJugTypes = const [],
    this.offersJugExchange = false,
    this.acceptsNewOrders = true,
    this.operatingDays,
    this.opensAt,
    this.closesAt,
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
      isActive: map['is_active'] as bool? ?? true,
      offeredJugTypes: List<String>.from(map['offered_jug_types'] as List? ?? const []),
      offersJugExchange: map['offers_jug_exchange'] as bool? ?? false,
      acceptsNewOrders: map['accepts_new_orders'] as bool? ?? true,
      operatingDays: (map['operating_days'] as List?)?.map((d) => (d as num).toInt()).toList(),
      opensAt: map['opens_at'] as String?,
      closesAt: map['closes_at'] as String?,
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
      'is_active': isActive,
      'offered_jug_types': offeredJugTypes,
      'offers_jug_exchange': offersJugExchange,
      'accepts_new_orders': acceptsNewOrders,
      'operating_days': operatingDays,
      'opens_at': opensAt,
      'closes_at': closesAt,
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
  final bool isActive;
  final List<String> offeredJugTypes;
  final bool offersJugExchange;
  final bool acceptsNewOrders;
  final List<int>? operatingDays;
  final String? opensAt;
  final String? closesAt;

  /// The association facts a customer can check (patch_public_trust.sql):
  /// standing in words, when it joined and was accredited, its last passed
  /// water test, and how long its sanitary permit runs.
  final String? standing;
  final DateTime? memberSince;
  final DateTime? accreditedAt;
  final DateTime? lastWaterTestAt;
  final DateTime? sanitaryValidUntil;

  /// Permanent ID, e.g. GW-STN-2026-0001 (patch_ids_and_addresses.sql).
  final String? stationCode;

  /// "Beside the chapel", to find the station from its address.
  final String? landmark;

  /// "New member" for the first 90 days after accreditation -- so a new
  /// station isn't read as an unknown one.
  bool isNewMember([DateTime? now]) =>
      isAccredited && accreditedAt != null && (now ?? DateTime.now()).difference(accreditedAt!).inDays < 90;

  /// See Station.isOrderable's doc comment -- same combined check.
  bool get isOrderable => isActive && acceptsNewOrders && isOpenNow;

  bool get isOpenNow => stationIsOpenNow(operatingDays: operatingDays, opensAt: opensAt, closesAt: closesAt);

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
    this.isActive = true,
    this.offeredJugTypes = const [],
    this.offersJugExchange = false,
    this.acceptsNewOrders = true,
    this.operatingDays,
    this.opensAt,
    this.closesAt,
    this.standing,
    this.memberSince,
    this.accreditedAt,
    this.lastWaterTestAt,
    this.sanitaryValidUntil,
    this.stationCode,
    this.landmark,
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
      isActive: map['is_active'] as bool? ?? true,
      offeredJugTypes: List<String>.from(map['offered_jug_types'] as List? ?? const []),
      offersJugExchange: map['offers_jug_exchange'] as bool? ?? false,
      acceptsNewOrders: map['accepts_new_orders'] as bool? ?? true,
      operatingDays: (map['operating_days'] as List?)?.map((d) => (d as num).toInt()).toList(),
      opensAt: map['opens_at'] as String?,
      closesAt: map['closes_at'] as String?,
      standing: map['standing'] as String?,
      memberSince: _date(map['member_since']),
      accreditedAt: _date(map['accredited_at']),
      lastWaterTestAt: _date(map['last_water_test_at']),
      sanitaryValidUntil: _date(map['sanitary_valid_until']),
      stationCode: map['station_code'] as String?,
      landmark: map['landmark'] as String?,
    );
  }

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// The order a customer sees stations in (Rollout plan, fairness): accredited
/// first, then nearest, and stations the same distance apart -- or every
/// station, when there's no location -- in an order that changes each day,
/// so no one station always sits at the top by accident of its name.
List<PublicStation> orderStationsForCustomers(
  List<PublicStation> stations, {
  double Function(PublicStation)? distanceKm,
  DateTime? today,
}) {
  final day = today ?? DateTime.now();
  final seed = day.year * 10000 + day.month * 100 + day.day;
  // A polynomial hash of the id, XORed with the date and stirred by a few
  // Lehmer steps, so each day is a different shuffle. Not Object.hash or
  // String.hashCode: those are seeded per run, so the order would change on
  // every reload. Kept below 2^47 so it is exact on the web too, where ints
  // are doubles.
  int rotation(PublicStation s) {
    var h = 7;
    for (final unit in s.id.codeUnits) {
      h = (h * 131 + unit) % 2147483647;
    }
    var x = (h ^ seed) % 2147483647;
    for (var i = 0; i < 3; i++) {
      x = (x * 48271) % 2147483647;
    }
    return x;
  }
  final sorted = [...stations];
  sorted.sort((a, b) {
    if (a.isAccredited != b.isAccredited) return a.isAccredited ? -1 : 1;
    if (distanceKm != null) {
      // Tenths of a kilometre: closer than that is a tie, not a ranking.
      final byDistance = (distanceKm(a) * 10).round().compareTo((distanceKm(b) * 10).round());
      if (byDistance != 0) return byDistance;
    }
    return rotation(a).compareTo(rotation(b));
  });
  return sorted;
}

/// True if unset (no schedule declared -- always open, preserves the
/// pre-hours-feature behavior). `operatingDays` uses Dart's DateTime.weekday
/// convention (1=Monday...7=Sunday). `opensAt`/`closesAt` are "HH:mm:ss" (or
/// "HH:mm") strings as returned by Postgres's `time` type over PostgREST.
/// Handles an overnight window (e.g. opens 20:00, closes 02:00).
///
/// Uses the device's local clock -- the Philippines is a single timezone
/// with no DST, so for a hyper-local app like this, device-local time is a
/// reasonable stand-in for "Philippine time" without needing explicit
/// timezone-conversion machinery.
bool stationIsOpenNow({required List<int>? operatingDays, required String? opensAt, required String? closesAt}) {
  final now = DateTime.now();

  if (operatingDays != null) {
    // Distinguish "no schedule ever declared" (null -- always open, the
    // pre-hours-feature default) from "every day explicitly deselected"
    // (empty list -- the owner means never open), which used to fall
    // through the isNotEmpty check below and be silently treated as the
    // former.
    if (operatingDays.isEmpty) return false;
    if (!operatingDays.contains(now.weekday)) return false;
  }

  final openMinutes = _parseMinutesSinceMidnight(opensAt);
  final closeMinutes = _parseMinutesSinceMidnight(closesAt);
  if (openMinutes == null || closeMinutes == null) return true;

  final nowMinutes = now.hour * 60 + now.minute;
  if (closeMinutes > openMinutes) {
    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  } else {
    // Overnight window (closes after midnight).
    return nowMinutes >= openMinutes || nowMinutes < closeMinutes;
  }
}

int? _parseMinutesSinceMidnight(String? time) {
  if (time == null) return null;
  final parts = time.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

/// A single, unambiguous availability label for a station -- resolves the
/// two independent reasons a station can be unorderable (the owner's own
/// "accepting orders" toggle, vs. being outside declared hours) into one
/// status so screens stop showing two different/contradicting badges for
/// the same station (admin suspension isn't part of this since
/// public_stations already filters those stations out entirely).
({String label, bool isOpen}) stationAvailabilityStatus({required bool acceptsNewOrders, required bool isOpenNow}) {
  if (!acceptsNewOrders) return (label: 'Not accepting orders', isOpen: false);
  if (!isOpenNow) return (label: 'Closed', isOpen: false);
  return (label: 'Open Now', isOpen: true);
}

const _weekdayShortNames = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

/// "Every day", "Mon, Wed, Fri", or "Hours not set" -- used anywhere a
/// station's schedule needs to be shown to a customer/visitor.
String formatOperatingDays(List<int>? days) {
  if (days == null || days.length == 7) return 'Every day';
  if (days.isEmpty) return 'Closed (no days selected)';
  final sorted = [...days]..sort();
  return sorted.map((d) => _weekdayShortNames[d] ?? '?').join(', ');
}

/// "7:00 AM" from a Postgres "HH:mm:ss"/"HH:mm" time string, or null if
/// unparseable.
String? formatTimeOfDay(String? time) {
  final minutes = _parseMinutesSinceMidnight(time);
  if (minutes == null) return null;
  final hour24 = minutes ~/ 60;
  final minute = minutes % 60;
  final period = hour24 < 12 ? 'AM' : 'PM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

/// "Mon, Wed, Fri · 7:00 AM - 7:00 PM", or just the days if hours aren't
/// set, or null if nothing has been configured at all.
String? formatStationHours({required List<int>? operatingDays, required String? opensAt, required String? closesAt}) {
  final open = formatTimeOfDay(opensAt);
  final close = formatTimeOfDay(closesAt);
  if (operatingDays == null && open == null && close == null) return null;
  final daysText = formatOperatingDays(operatingDays);
  if (open == null || close == null) return daysText;
  return '$daysText · $open - $close';
}
