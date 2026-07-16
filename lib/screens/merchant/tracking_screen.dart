import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  Set<Marker> _markers = {};
  
  // Default Station Coordinates (General Trias)
  final LatLng _stationLocation = const LatLng(14.3152, 120.9156);
  final RouteOptimizationService _routeService = RouteOptimizationService();
  final supabase = Supabase.instance.client;

  Future<void> _generateRealRoute() async {
    setState(() => _isGeneratingRoute = true);
    
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Get the Merchant's Station ID
      final stationData = await supabase
          .from('water_stations')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (stationData == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No station found for this account.')));
        setState(() => _isGeneratingRoute = false);
        return;
      }
      final stationId = stationData['id'];

      // 2. Call the SQL Function (RPC) to get clean latitude and longitude
      final response = await supabase.rpc(
        'get_active_orders',
        params: {'merchant_station_id': stationId},
      );

      final List<dynamic> orders = response as List<dynamic>;

      if (orders.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pending orders to route!')),
        );
        setState(() => _isGeneratingRoute = false);
        return;
      }

      // 3. Convert database response to the format your Route Service needs
      List<Map<String, double>> customerLocations = [];
      Set<Marker> newMarkers = {
        Marker(
          markerId: const MarkerId('station'),
          position: _stationLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Water Station'),
        )
      };

      for (int i = 0; i < orders.length; i++) {
        double lat = double.parse(orders[i]['lat'].toString());
        double lng = double.parse(orders[i]['lng'].toString());
        
        customerLocations.add({"lat": lat, "lng": lng});
        
        // Add a red marker for each customer order with their jug count
        newMarkers.add(
          Marker(
            markerId: MarkerId('customer_$i'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: 'Order: ${orders[i]['jugs_ordered']} Jugs'),
          ),
        );
      }

      // 4. Call your working Google Route API
      final String poly = await _routeService.calculateFleetRoute(
        {"lat": _stationLocation.latitude, "lng": _stationLocation.longitude},
        customerLocations,
      );

      // 5. Draw the route on the map
      if (poly.isNotEmpty) {
        setState(() {
          _markers = newMarkers;
          _polylines = {
            Polyline(
              polylineId: const PolylineId('dynamic_route'),
              color: Colors.blueAccent,
              width: 8,
              points: decodeEncodedPolyline(poly),
            ),
          };
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Routing Error: $e')));
    } finally {
      if(mounted) setState(() => _isGeneratingRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Fleet Tracking')),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _stationLocation, zoom: 14.0),
        polylines: _polylines,
        markers: _markers,
        onMapCreated: (c) {
          _mapController = c;
          _generateRealRoute(); // Auto-fetch on load
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGeneratingRoute ? null : _generateRealRoute,
        label: Text(_isGeneratingRoute ? 'Calculating Route...' : 'Refresh Route'),
        icon: _isGeneratingRoute
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.route),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }
}