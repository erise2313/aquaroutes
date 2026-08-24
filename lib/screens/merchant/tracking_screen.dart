import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/route_optimization.dart';
import '../../widgets/custom_map_marker.dart';

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

      final stops = <Map<String, double>>[];
      for (final o in orders) {
        stops.add({'lat': double.parse(o['lat'].toString()), 'lng': double.parse(o['lng'].toString())});
      }

      // Best-effort visiting order via straight-line distance -- see
      // route_optimization.dart for why there's no real road polyline here.
      var orderedStops = stops;
      try {
        final sequence = _routeService.computeStopSequence(
          {'lat': dynamicStationLocation.latitude, 'lng': dynamicStationLocation.longitude},
          stops,
        );
        if (sequence.length == stops.length) {
          orderedStops = sequence.map((i) => stops[i]).toList();
        }
      } catch (e) {
        debugPrint('Stop sequencing skipped: $e');
      }

      if (mounted) {
        setState(() {
          _stationLocation = dynamicStationLocation;
          _stopPoints = orderedStops.map((s) => LatLng(s['lat']!, s['lng']!)).toList();
        });
        _mapController.move(dynamicStationLocation, 14);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Routing Error: $e')));
    } finally {
      if (mounted) setState(() => _isGeneratingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Fleet Tracking')),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _stationLocation, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'ph.gentriwasa.aquaroute',
          ),
          PolylineLayer(
            polylines: [
              Polyline(points: [_stationLocation, ..._stopPoints], color: Colors.blueAccent, strokeWidth: 4),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGeneratingRoute ? null : _generateRoute,
        label: Text(_isGeneratingRoute ? 'Refreshing...' : 'Refresh Route'),
        icon: _isGeneratingRoute
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.route),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }
}
