import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// GPS broadcast for the ON-DUTY toggle. Upserts into `driver_states`
/// (supabase/migrations/0006_orders_driver_state.sql), keyed by worker_id
/// (not the old driver_id/profile-based key). Unlike the old version, the
/// stream subscription is now stored so it can actually be cancelled --
/// previously `startTracking` discarded the subscription, so there was no
/// way to turn broadcasting off once a screen opened.
class LocationService {
  final _supabase = Supabase.instance.client;
  StreamSubscription<Position>? _subscription;

  bool get isTracking => _subscription != null;

  void startTracking(String workerId) {
    if (_subscription != null) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Only update if the driver moved 10 meters.
    );

    _subscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((position) async {
      await _supabase.from('driver_states').upsert({
        'worker_id': workerId,
        'current_location': 'POINT(${position.longitude} ${position.latitude})',
        'current_speed': position.speed,
        'last_updated': DateTime.now().toIso8601String(),
        'is_active': true,
      });
    });
  }

  /// Stops broadcasting and marks the driver off-duty server-side.
  Future<void> stopTracking(String workerId) async {
    await _subscription?.cancel();
    _subscription = null;
    await _supabase.from('driver_states').update({'is_active': false}).eq('worker_id', workerId);
  }
}
