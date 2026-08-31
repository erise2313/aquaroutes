import 'package:geolocator/geolocator.dart';

import '../models/station.dart';

/// Distance-based "near me" sorting for the station directory/order form.
/// Reuses the permission-request pattern already proven in
/// location_picker_screen.dart, and Geolocator's own distanceBetween()
/// (no need to hand-roll Haversine again -- route_optimization.dart's
/// version is private to that class and serves a different purpose).
class NearbyService {
  /// Returns the device's current position, or null if location is
  /// unavailable/denied -- callers should fall back to unsorted/default
  /// behavior rather than blocking on this.
  Future<Position?> getCurrentPositionOrNull() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (_) {
      return null;
    }
  }

  /// Distance from (lat, lng) to a station, in kilometers.
  double distanceKm(double lat, double lng, PublicStation station) {
    return Geolocator.distanceBetween(lat, lng, station.latitude, station.longitude) / 1000;
  }

  /// Sorts stations nearest-first relative to (lat, lng).
  List<PublicStation> sortByDistance(List<PublicStation> stations, double lat, double lng) {
    final sorted = [...stations];
    sorted.sort((a, b) => distanceKm(lat, lng, a).compareTo(distanceKm(lat, lng, b)));
    return sorted;
  }

  String formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }
}
