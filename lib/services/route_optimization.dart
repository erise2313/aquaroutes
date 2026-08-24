import 'dart:math';

// TODO(route-optimization-followup): This used to call Google's Route
// Optimization API directly from the client using a hardcoded Google Cloud
// service-account private key embedded in source -- a critical secret leak
// (the key must still be rotated/revoked in GCP Console if that hasn't
// happened already). That call is removed. Re-implement real multi-stop
// route optimization behind a backend function (e.g. a Supabase Edge
// Function) that holds the credential server-side and returns only the
// ordered stop sequence -- or call an OSM-based routing engine
// (OSRM/Valhalla) server-side to stay consistent with the flutter_map/OSM
// migration. Never reintroduce credential material into the Flutter app.
//
// Until then, this returns a simple nearest-neighbor stop order computed
// from straight-line (Haversine) distance, with no real road polyline.
// Method names/signatures are kept the same as before so callers
// (driver_dashboard.dart, tracking_screen.dart) don't need to change yet.
class RouteOptimizationService {
  Future<String> calculateFleetRoute(
    Map<String, double> stationLocation,
    List<Map<String, double>> customerLocations,
  ) async {
    // No real route polyline is available without a backend routing engine.
    return '';
  }

  Future<Map<String, dynamic>> calculateDriverManifest(
    Map<String, double> stationLocation,
    List<Map<String, double>> customerLocations,
  ) async {
    if (customerLocations.isEmpty) return {'polyline': '', 'sequence': <int>[]};

    return {
      'polyline': '',
      'sequence': computeStopSequence(stationLocation, customerLocations),
    };
  }

  /// Nearest-neighbor ordering of `stops` starting from `origin`, using
  /// straight-line Haversine distance. Returns the visiting order as a list
  /// of indices into `stops`.
  List<int> computeStopSequence(
    Map<String, double> origin,
    List<Map<String, double>> stops,
  ) {
    if (stops.isEmpty) return [];

    final remaining = List<int>.generate(stops.length, (i) => i);
    final sequence = <int>[];
    var currentLat = origin['lat']!;
    var currentLng = origin['lng']!;

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) => _distanceMeters(currentLat, currentLng, stops[a]['lat']!, stops[a]['lng']!)
          .compareTo(_distanceMeters(currentLat, currentLng, stops[b]['lat']!, stops[b]['lng']!)));
      final next = remaining.removeAt(0);
      sequence.add(next);
      currentLat = stops[next]['lat']!;
      currentLng = stops[next]['lng']!;
    }

    return sequence;
  }

  double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}
