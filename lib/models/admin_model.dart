class FleetTelemetry {
  final String vehicleId;
  final double lat;
  final double lng;
  final double velocity;
  final int payload; // Number of jugs

  FleetTelemetry({
    required this.vehicleId,
    required this.lat,
    required this.lng,
    required this.velocity,
    required this.payload,
  });

  // This will eventually be replaced by Supabase parsing
  factory FleetTelemetry.fromJson(Map<String, dynamic> json) {
    return FleetTelemetry(
      vehicleId: json['vehicle_id'],
      lat: json['lat'],
      lng: json['lng'],
      velocity: json['velocity'],
      payload: json['payload'],
    );
  }
}