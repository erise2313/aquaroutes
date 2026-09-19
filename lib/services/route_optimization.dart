import 'dart:async';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/log.dart';

/// Road routing for deliveries.
///
/// The visiting order and the road geometry come from the `route-optimize`
/// Supabase Edge Function (supabase/functions/route-optimize/index.ts), which
/// holds any routing API key server-side. That function replaces a Google
/// Route Optimization call that shipped a service-account private key inside
/// this app -- never put credential material back in the client.
///
/// When the function can't be reached, [RouteOptimizationService.planRoute]
/// falls back to a nearest-neighbour order with straight lines between stops
/// and marks the plan [RoutePlan.isApproximate], so the map can say so rather
/// than passing straight lines off as a route. Before the function existed,
/// that straight-line drawing was all the app ever showed.
class RoutePlan {
  const RoutePlan({
    required this.sequence,
    required this.points,
    required this.isApproximate,
    this.distanceMeters,
    this.durationSeconds,
    this.provider,
  });

  /// Visiting order, as indices into the stops passed to `planRoute`.
  final List<int> sequence;

  /// The line to draw, from the origin through every stop.
  final List<LatLng> points;

  /// True for the straight-line fallback: the order is a straight-line
  /// estimate and [points] are not roads.
  final bool isApproximate;

  final int? distanceMeters;
  final int? durationSeconds;

  /// Which routing backend produced the plan ("osrm", "openrouteservice").
  final String? provider;

  static const empty = RoutePlan(sequence: [], points: [], isApproximate: false);

  /// "9.2 km · 15 min by road", or null when there's no real route to
  /// describe -- a straight-line distance would understate the real drive.
  String? get summary {
    if (isApproximate || distanceMeters == null || durationSeconds == null) return null;
    final km = (distanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (durationSeconds! / 60).round();
    return '$km km · ${minutes < 1 ? '<1' : minutes} min by road';
  }
}

/// Nearest-neighbour ordering of [stops] starting from [origin], by
/// straight-line (Haversine) distance. Only used for the fallback.
List<int> nearestNeighbourSequence(LatLng origin, List<LatLng> stops) {
  final remaining = List<int>.generate(stops.length, (i) => i);
  final sequence = <int>[];
  var current = origin;
  while (remaining.isNotEmpty) {
    remaining.sort((a, b) => _distanceMeters(current, stops[a]).compareTo(_distanceMeters(current, stops[b])));
    final next = remaining.removeAt(0);
    sequence.add(next);
    current = stops[next];
  }
  return sequence;
}

/// The honest fallback: nearest-neighbour order, straight segments, flagged.
RoutePlan approximateRoutePlan(LatLng origin, List<LatLng> stops) {
  final sequence = nearestNeighbourSequence(origin, stops);
  return RoutePlan(
    sequence: sequence,
    points: [origin, for (final i in sequence) stops[i]],
    isApproximate: true,
  );
}

/// Validates and converts the Edge Function's JSON into a [RoutePlan].
///
/// Throws [FormatException] on anything it can't trust -- in particular a
/// `sequence` that isn't an exact permutation of the stops, which would
/// otherwise silently drop or duplicate a delivery.
RoutePlan routePlanFromResponse(dynamic data, int stopCount) {
  if (data is! Map) throw const FormatException('Route response is not an object');

  final rawSequence = data['sequence'];
  if (rawSequence is! List || rawSequence.length != stopCount) {
    throw const FormatException('Route sequence does not cover every stop');
  }
  final sequence = <int>[];
  for (final v in rawSequence) {
    if (v is! int || v < 0 || v >= stopCount) throw const FormatException('Route sequence index out of range');
    sequence.add(v);
  }
  if (sequence.toSet().length != stopCount) throw const FormatException('Route sequence repeats a stop');

  final rawPoints = data['points'];
  if (rawPoints is! List || rawPoints.length < 2) throw const FormatException('Route has no geometry');
  final points = <LatLng>[];
  for (final p in rawPoints) {
    if (p is! List || p.length < 2 || p[0] is! num || p[1] is! num) {
      throw const FormatException('Route point is malformed');
    }
    points.add(LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()));
  }

  return RoutePlan(
    sequence: sequence,
    points: points,
    isApproximate: false,
    distanceMeters: (data['distance_m'] as num?)?.round(),
    durationSeconds: (data['duration_s'] as num?)?.round(),
    provider: data['provider'] as String?,
  );
}

/// Calls the routing backend with a JSON body and returns the decoded JSON.
/// Injectable so the fallback behaviour can be tested without Supabase.
typedef RouteFunctionInvoker = Future<dynamic> Function(Map<String, dynamic> body);

class RouteOptimizationService {
  RouteOptimizationService({RouteFunctionInvoker? invoker}) : _invoker = invoker;

  final RouteFunctionInvoker? _invoker;

  /// Order and road geometry for visiting [stops] from [origin]. Never
  /// throws: any failure yields [approximateRoutePlan], flagged as such.
  Future<RoutePlan> planRoute(LatLng origin, List<LatLng> stops) async {
    if (stops.isEmpty) return RoutePlan.empty;
    try {
      final data = await (_invoker ?? _invokeEdgeFunction)({
        'origin': {'lat': origin.latitude, 'lng': origin.longitude},
        'stops': [for (final s in stops) {'lat': s.latitude, 'lng': s.longitude}],
      }).timeout(const Duration(seconds: 15));
      return routePlanFromResponse(data, stops.length);
    } catch (e) {
      // No coordinates in the message: stops are customer addresses.
      logError('route optimize', 'unavailable (${e.runtimeType}); using straight-line estimate');
      return approximateRoutePlan(origin, stops);
    }
  }

  Future<dynamic> _invokeEdgeFunction(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke('route-optimize', body: body);
    return response.data;
  }
}

double _distanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(b.latitude - a.latitude);
  final dLng = _toRadians(b.longitude - a.longitude);
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(a.latitude)) * cos(_toRadians(b.latitude)) * sin(dLng / 2) * sin(dLng / 2);
  return earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(1 - h));
}

double _toRadians(double degrees) => degrees * pi / 180;
