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
    "private_key_id": "45276c6eea52d1a9cb523540217312321a005ebb",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDlpxoOFnRXaBR0\n1hLmDApvNse0Hj0Tp8KJiIsGgWWHYEmP/ruH8fDbVtPbGEAPIHw2DX1HnFZu6In/\n9Pe5FejBq365ca6L5UffhZ5WGmrxyihi7qtC28vtJ+vps+Jvotor6H54Bx+LcJhN\nCVFqF2qvvd1QgqqoQOuWllCWZtC+QhCD20B7KohHxe3bZcKbT9wpTCv6Lw5UX0jj\nU8dQTDGKTnXVqKfaSOq8shZWEPfxVAIXbQqTbR7Hcmp7Yzen/C2J68HVGjay43fn\n4Z5yvtM0bUAyzO7KgN7DRIVHhYdRd4mRqW3wnRgchg6q/ruDudGQw4NXNyjBv8yV\nPvNp2m4XAgMBAAECggEARUYfxOofFBKwQQImV0CAkUWr/fg1Ik2zj/shPMghkTGJ\nXydO+FYR+of5hhiNkkKRVVjCVqyhIfmBTzVc2Hb0bB9ILbZOGaMDCDjtJzn20pLR\nle46uQNGQ3aMYkXB4zzzpNUP+TLk4BIJzwslhOQlaXfTX6rawcA7kIQtMQE4rHr8\n1r9aBNcDSrXKN2b3tc0WO4A1yjDGRJmcjDKkXqKTRPAcNooAynrgEuSZMVfTtp8M\nPyGPpKIA7QCVaZmu4yhqacfWWTXAJUKFhZhXnSqsS0LyAKVqmyw9QexqSpUqDkKZ\nVSs9Pb3/v2QThu6i4lPkFpY/7yxK+W7QO5gULdrRwQKBgQD6aG/tVETahWhk6Ccn\nueo4juyfy8KUICEdm7aVSnRVry/HyzMcp3wk6Gd2oLLyCb+9lkyV3v4ktpH6cZ4z\nKJmxnQ22EJoZVlYt+hGF/hBD7patLM1POZHGhTQi2iE/2eEeXOjxUtxzmCYMRrLw\n087NvM0Z8FWQz7QZowCr4xmYtwKBgQDqyAI0CBpKh8ErfZu5UJ+dJYK3ABiIRoDY\nL1F1f9rQA21LcogzJegM4vRkPqvZZ3JAM+yH8gNlxHRoMDczVpbyxhsnPvaV71BM\nlQT6lmYZ0jIIn622ykAxOFTiiZO31oZ7rlCmJU4zcwmwR0lzQ96n2p0/SM80B7nc\nsL2GWHi1oQKBgBaS26Q1eI+Kf0K5eu4l4GuA1uwA3mWkD9gvdWI3+AzRYilMtCrd\nHl/lY45aJkeTgWmB5x2LoLWGj9pX678I5fIRCm9jR8EI+3PhmzrNEIJPO94Yr9l4\ngx+2WmDZ8S1kYtrt3UIECkORb7yjkvYK4hXB82tnMw9+6el1vFXCf0g5AoGAMAh7\naum9d0IO4zbvhRpZjWz/MTFz022ZLqF/qOpfee85jRYBh3VZ5EkKdvfbcL8ZQMle\nuvFogImQx0AWCwrMFx8wrvbSvBoZ85EJU7sxaFb4pYsFn0ABohBETZSYBCR/nw4q\nsdMwDJachNQQ0uQvyWeQhEIBIkPyYpRGMhYnnAECgYEA0VVgvU6+oaA4+TafOJZz\now+mlLNOrZ2NL27nLOqyI7zqQjaaYrEq/x0tVlyfohPrUDS2gVZ4bkEzvpkYeYUb\nk27CaHjRdHVcp6cVf/gCqTxaiOd7zJ2JQC+r/2C/ZEF6omp974Rqwtt6z+A9Qn/j\nZ9lA693qQhpLWgwXfPF5QnU=\n-----END PRIVATE KEY-----\n",
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
