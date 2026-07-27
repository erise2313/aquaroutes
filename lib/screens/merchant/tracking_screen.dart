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

    // 1. Get the Merchant's Station ID AND their actual saved coordinates
    final stationData = await supabase
        .from('water_stations')
        .select('id, latitude, longitude')
        .eq('owner_id', userId)
        .maybeSingle();

    if (stationData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No station found for this account.')));
      setState(() => _isGeneratingRoute = false);
      return;
    }
    
    final stationId = stationData['id'];
    
    // Fall back to General Trias default if coordinates haven't been set yet
    final double stationLat = (stationData['latitude'] as num?)?.toDouble() ?? 14.3152;
    final double stationLng = (stationData['longitude'] as num?)?.toDouble() ?? 120.9156;
    final LatLng dynamicStationLocation = LatLng(stationLat, stationLng);

    // 2. Call the SQL Function (RPC) to get active orders
    final response = await supabase.rpc(
      'get_active_orders',
      params: {'merchant_station_id': stationId},
    );

    final List<dynamic> orders = response as List<dynamic>;

    // 3. Build markers using the DYNAMIC station location instead of the hardcoded one
    List<Map<String, double>> customerLocations = [];
    Set<Marker> newMarkers = {
      Marker(
        markerId: const MarkerId('station'),
        position: dynamicStationLocation, // <-- Uses real DB coordinates here!
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Water Station'),
      )
    };

    for (int i = 0; i < orders.length; i++) {
      double lat = double.parse(orders[i]['lat'].toString());
      double lng = double.parse(orders[i]['lng'].toString());
      
      customerLocations.add({"lat": lat, "lng": lng});
      
      newMarkers.add(
        Marker(
          markerId: MarkerId('customer_$i'),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(title: 'Order: ${orders[i]['jugs_ordered']} Jugs'),
        ),
      );
    }

    // 4. Call Google Route API using the real station coordinates
    final String poly = await _routeService.calculateFleetRoute(
      {"lat": dynamicStationLocation.latitude, "lng": dynamicStationLocation.longitude},
      customerLocations,
    );

    // 5. Draw the route on the map and update the camera view
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
      
      // Optionally animate map camera to center on the real station location
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(dynamicStationLocation, 14.0),
      );
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