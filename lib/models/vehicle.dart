/// Vehicle/driver info, sourced from the `workers` table
/// (supabase/migrations/0005_workers.sql). Previously this held ad-hoc
/// telemetry fields pulled from a flat `user_profiles` row; those fields
/// (vehicle_plate, jug_capacity) now live on `workers` directly.
class Vehicle {
  final String workerId;
  final String? vehiclePlate;
  final int? jugCapacity;
  final double? currentLat;
  final double? currentLng;
  final double? currentSpeed;
  final bool isActive;
  final DateTime? lastUpdated;

  const Vehicle({
    required this.workerId,
    this.vehiclePlate,
    this.jugCapacity,
    this.currentLat,
    this.currentLng,
    this.currentSpeed,
    required this.isActive,
    this.lastUpdated,
  });

  /// `current_lat`/`current_lng` are expected as aliased columns from a
  /// query selecting `st_y(current_location::geometry) as current_lat,
  /// st_x(current_location::geometry) as current_lng` against `driver_states`.
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      workerId: map['worker_id'] as String,
      vehiclePlate: map['vehicle_plate'] as String?,
      jugCapacity: map['jug_capacity'] as int?,
      currentLat: (map['current_lat'] as num?)?.toDouble(),
      currentLng: (map['current_lng'] as num?)?.toDouble(),
      currentSpeed: (map['current_speed'] as num?)?.toDouble(),
      isActive: map['is_active'] as bool? ?? false,
      lastUpdated: map['last_updated'] == null ? null : DateTime.parse(map['last_updated'] as String),
    );
  }
}
