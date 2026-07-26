import 'dart:convert';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:googleapis_auth/auth_io.dart';

// No custom exception class needed; we will return messages or throw generic Exceptions
List<LatLng> decodeEncodedPolyline(String encodedString) {
  if (encodedString.trim().isEmpty) {
    return [];
  }

  final List<PointLatLng> result = PolylinePoints.decodePolyline(encodedString);
  return result
      .map((PointLatLng point) => LatLng(point.latitude, point.longitude))
      .toList();
}

class RouteOptimizationService {
  final _credentials = ServiceAccountCredentials.fromJson({
    "type": "service_account",
    "project_id": "aquaroute-501315",
    "private_key_id": "***REDACTED***",
    "private_key": "***REDACTED***",
    "client_email": "aquaroute-router@aquaroute-501315.iam.gserviceaccount.com",
    "client_id": "110343435732566565547",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url":
        "https://www.googleapis.com/robot/v1/metadata/x509/aquaroute-router%40aquaroute-501315.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com",
  });

  final _scopes = ['https://www.googleapis.com/auth/cloud-platform'];
  final String endpoint =
      "https://routeoptimization.googleapis.com/v1/projects/aquaroute-501315:optimizeTours";

  // Original Merchant API Call
  Future<String> calculateFleetRoute(
    Map<String, double> stationLocation,
    List<Map<String, double>> customerLocations,
  ) async {
    if (customerLocations.isEmpty) {
      throw Exception('At least one customer location is required.');
    }

    final now = DateTime.now().toUtc();
    final globalStartTime = "${now.toIso8601String().split('.')[0]}Z";
    final globalEndTime = "${now.add(const Duration(hours: 12)).toIso8601String().split('.')[0]}Z";

    final List<Map<String, dynamic>> vehicles = [
      {
        "startLocation": {
          "latitude": stationLocation['lat'],
          "longitude": stationLocation['lng'],
        },
        "endLocation": {
          "latitude": stationLocation['lat'],
          "longitude": stationLocation['lng'],
        },
        "costPerKilometer": 1.0,
        "costPerHour": 1.0,
      },
    ];

    final List<Map<String, dynamic>> shipments = customerLocations.map((loc) {
      return {
        "deliveries": [
          {
            "arrivalLocation": {
              "latitude": loc['lat'],
              "longitude": loc['lng'],
            },
            "duration": "300s",
          },
        ],
      };
    }).toList();

    final Map<String, dynamic> requestBody = {
      "populatePolylines": true,
      "populateTransitionPolylines": true,
      "considerRoadTraffic": true,
      "model": {
        "globalStartTime": globalStartTime,
        "globalEndTime": globalEndTime,
        "vehicles": vehicles,
        "shipments": shipments,
      },
    };

    final authClient = await clientViaServiceAccount(_credentials, _scopes);
    try {
      final response = await authClient.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Route optimization failed (${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final encodedPolyline = _extractRoutePolyline(data);

      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        throw Exception('Google returned a route without an encoded polyline.');
      }

      return encodedPolyline;
    } catch (e) {
      rethrow; // Re-throwing ensures your tracking_screen catches the message
    } finally {
      authClient.close();
    }
  }

  // =====================================================================
  // NEW DRIVER MANIFEST API CALL
  // Returns both the polyline AND the sorted queue sequence
  // =====================================================================
  Future<Map<String, dynamic>> calculateDriverManifest(
    Map<String, double> stationLocation,
    List<Map<String, double>> customerLocations,
  ) async {
    if (customerLocations.isEmpty) return {'polyline': '', 'sequence': <int>[]};

    final now = DateTime.now().toUtc();
    final globalStartTime = "${now.toIso8601String().split('.')[0]}Z";
    final globalEndTime = "${now.add(const Duration(hours: 12)).toIso8601String().split('.')[0]}Z";

    final List<Map<String, dynamic>> vehicles = [
      {
        "startLocation": {"latitude": stationLocation['lat'], "longitude": stationLocation['lng']},
        "endLocation": {"latitude": stationLocation['lat'], "longitude": stationLocation['lng']},
        "costPerKilometer": 1.0,
        "costPerHour": 1.0, 
      },
    ];

    final List<Map<String, dynamic>> shipments = customerLocations.map((loc) {
      return {
        "deliveries": [{"arrivalLocation": {"latitude": loc['lat'], "longitude": loc['lng']}, "duration": "300s"}],
      };
    }).toList();

    final Map<String, dynamic> requestBody = {
      "populatePolylines": true,
      "populateTransitionPolylines": true,
      "considerRoadTraffic": true, // Maintained your traffic settings!
      "model": {
        "globalStartTime": globalStartTime,
        "globalEndTime": globalEndTime,
        "vehicles": vehicles,
        "shipments": shipments,
      },
    };

    final authClient = await clientViaServiceAccount(_credentials, _scopes);
    try {
      final response = await authClient.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) return {'polyline': '', 'sequence': <int>[]};

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final String polyline = _extractRoutePolyline(data) ?? '';

      // Extrapolate the AI's optimized sequence from the 'visits' array
      List<int> sequence = [];
      try {
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final visits = routes[0]['visits'] as List?;
          if (visits != null) {
            for (var visit in visits) {
              if (visit.containsKey('shipmentIndex')) {
                sequence.add(visit['shipmentIndex'] as int);
              }
            }
          }
        }
      } catch (e) {
        // Safe fallback: keeps the original chronological order if parsing fails
        sequence = List.generate(customerLocations.length, (i) => i);
      }

      return {'polyline': polyline, 'sequence': sequence};
    } finally {
      authClient.close();
    }
  }

  String? _extractRoutePolyline(Map<String, dynamic> data) {
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;

    final route = routes.first;
    if (route is! Map<String, dynamic>) return null;

    final routePolyline = route['routePolyline'];
    if (routePolyline is Map<String, dynamic>) {
      final points = routePolyline['points'];
      if (points is String && points.isNotEmpty) return points;
    }
    return null;
  }
}