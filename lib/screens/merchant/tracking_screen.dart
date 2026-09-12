import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../services/route_optimization.dart';
import '../../widgets/app_map_tiles.dart';
import '../../widgets/custom_map_marker.dart';
import '../../utils/error_text.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final MapController _mapController = MapController();
  bool _isGeneratingRoute = false;

  LatLng _stationLocation = const LatLng(14.3868, 120.8817);
  List<LatLng> _stopPoints = [];

  /// The line actually drawn: road geometry from the route-optimize Edge
  /// Function, or -- when that's unreachable -- a straight-line estimate that
  /// [_routeApproximate] flags so the map can say so.
  List<LatLng> _routePoints = [];
  bool _routeApproximate = false;
  String? _routeSummary;

  final RouteOptimizationService _routeService = RouteOptimizationService();
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _generateRoute();
  }

  Future<void> _generateRoute() async {
    setState(() => _isGeneratingRoute = true);

    try {
      final userId = supabase.auth.currentUser!.id;

      final stationData = await supabase
          .from('water_stations')
          .select('id, latitude, longitude')
          .eq('owner_profile_id', userId)
          .maybeSingle();

      if (stationData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No station found for this account.')));
          setState(() => _isGeneratingRoute = false);
        }
        return;
      }

      final stationId = stationData['id'];
      final double stationLat = (stationData['latitude'] as num?)?.toDouble() ?? 14.3868;
      final double stationLng = (stationData['longitude'] as num?)?.toDouble() ?? 120.8817;
      final dynamicStationLocation = LatLng(stationLat, stationLng);

      final response = await supabase.rpc('get_active_orders', params: {'p_station_id': stationId});
      final List<dynamic> orders = List<dynamic>.from(response as List);

      final stops = <LatLng>[
        for (final o in orders) LatLng(double.parse(o['lat'].toString()), double.parse(o['lng'].toString())),
      ];

      // Never throws -- falls back to a flagged straight-line estimate.
      final plan = await _routeService.planRoute(dynamicStationLocation, stops);

      if (mounted) {
        setState(() {
          _stationLocation = dynamicStationLocation;
          _stopPoints = [for (final i in plan.sequence) stops[i]];
          _routePoints = plan.points;
          _routeApproximate = plan.isApproximate;
          _routeSummary = plan.summary;
        });
        _mapController.move(dynamicStationLocation, 14);
      }
    } catch (e) {
      debugPrint(describeError(e));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Routing Error. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _isGeneratingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No portal header here: the map is the whole screen, and a hero band
      // would take a quarter of it on a phone for a title the tab bar already
      // gives. Only the colours move onto the palette.
      appBar: AppBar(title: const Text('Live Fleet Tracking')),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _stationLocation, initialZoom: 14),
        children: [
          const AppMapTiles(),
          if (_routePoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(points: _routePoints, color: AppColors.primary, strokeWidth: 4),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(point: _stationLocation, width: 44, height: 44, child: const MapPin(kind: MapPinKind.station)),
              for (var i = 0; i < _stopPoints.length; i++)
                Marker(
                  point: _stopPoints[i],
                  width: 44,
                  height: 44,
                  child: MapPin(kind: i == 0 ? MapPinKind.currentStop : MapPinKind.queuedStop),
                ),
            ],
          ),
          if (_stopPoints.isNotEmpty) RouteStatusBanner(isApproximate: _routeApproximate, summary: _routeSummary),
          const AppMapAttribution(showRoutingCredit: true),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGeneratingRoute ? null : _generateRoute,
        label: Text(_isGeneratingRoute ? 'Refreshing...' : 'Refresh Route'),
        icon: _isGeneratingRoute
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.route),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
