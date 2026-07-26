import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  final _supabase = Supabase.instance.client;

  // Initialize and start watching location
  void startTracking(String driverId) {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, 
      distanceFilter: 10, // Only update if driver moved 10 meters 
    );

    Geolocator.getPositionStream(locationSettings: locationSettings).listen((
      Position position,
    ) async {
      // Upsert into driver_states table to ensure real-time visibility
      await _supabase.from('driver_states').upsert({
        'driver_id': driverId,
        'current_location': 'POINT(${position.longitude} ${position.latitude})',
        'current_speed': position.speed,
        'last_updated': DateTime.now().toIso8601String(),
        'is_active': true,
      });
    });
  }
}