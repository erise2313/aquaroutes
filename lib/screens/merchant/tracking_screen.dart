import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:aquaroute/services/route_optimization.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});
  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  GoogleMapController? _mapController;
  bool _isGeneratingRoute = false;
  Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};
  final LatLng _center = const LatLng(14.3152, 120.9156);
  final RouteOptimizationService _routeService = RouteOptimizationService();

  Future<void> _generateRealRoute() async {
    setState(() => _isGeneratingRoute = true);
    try {
      final String poly = await _routeService.calculateFleetRoute(
        {"lat": 14.3152, "lng": 120.9156},
        [
          {"lat": 14.3200, "lng": 120.9200},
        ],
      );
      if (poly.isNotEmpty) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blueAccent,
              width: 8,
              points: decodeEncodedPolyline(poly),
            ),
          };
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _isGeneratingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Fleet Tracking')),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
        polylines: _polylines,
        markers: _markers,
        onMapCreated: (c) => _mapController = c,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGeneratingRoute ? null : _generateRealRoute,
        label: Text(_isGeneratingRoute ? 'Generating...' : 'Generate Route'),
        icon: _isGeneratingRoute
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.route),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }
}
