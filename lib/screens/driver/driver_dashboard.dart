import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/location_service.dart';
import '../../services/route_optimization.dart';
import '../auth/login_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final supabase = Supabase.instance.client;
  final LocationService _locationService = LocationService();
  final RouteOptimizationService _routeService = RouteOptimizationService();
  
  bool _isLoading = true;
  Map<String, dynamic>? _currentActiveOrder;
  
  // UI Data
  String _customerName = "Loading...";
  double _totalAmount = 0.0;
  LatLng? _destination;
  GoogleMapController? _mapController;
  
  // Map Data
  Set<Marker> _allDropoffMarkers = {}; 
  Set<Polyline> _polylines = {}; 

  // Default Station Coordinates (Origin)
  final LatLng _stationLocation = const LatLng(14.3152, 120.9156);

  @override
  void initState() {
    super.initState();
    _initializeDriver();
  }

  Future<void> _initializeDriver() async {
    await _requestLocationPermissionAndStartTracking();
    await _fetchActiveDelivery();
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
    }
  }

  Future<void> _requestLocationPermissionAndStartTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final driverId = supabase.auth.currentUser!.id;
    _locationService.startTracking(driverId);
  }

  Future<void> _fetchActiveDelivery() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. DATA ISOLATION: Find boss
      final profile = await supabase
          .from('user_profiles')
          .select('assigned_station_id')
          .eq('id', userId)
          .maybeSingle();

      if (profile == null || profile['assigned_station_id'] == null) {
        throw Exception("You are not linked to a water station.");
      }
      final myBossStationId = profile['assigned_station_id'];

      // 2. Fetch the map coordinates from the database
      final response = await supabase.rpc(
        'get_active_orders',
        params: {'merchant_station_id': myBossStationId},
      );

      List<dynamic> activeOrders = response as List<dynamic>;

      if (activeOrders.isNotEmpty) {
        List<Map<String, double>> customerLocationsForRouting = [];
        for (var o in activeOrders) {
          customerLocationsForRouting.add({
            "lat": double.parse(o['lat'].toString()), 
            "lng": double.parse(o['lng'].toString())
          });
        }

        Set<Polyline> newPolylines = {};
        
        // 3. CALL GOOGLE FOR THE OPTIMIZED SEQUENCE
        try {
          final result = await _routeService.calculateDriverManifest(
            {"lat": _stationLocation.latitude, "lng": _stationLocation.longitude},
            customerLocationsForRouting,
          );
          
          final String poly = result['polyline'];
          final List<int> sequence = result['sequence'];

          if (poly.isNotEmpty) {
            newPolylines = {
              Polyline(
                polylineId: const PolylineId('driver_route'), 
                color: Colors.blueAccent, 
                width: 8, 
                points: decodeEncodedPolyline(poly)
              )
            };
          }

          // 4. THE FIX: REORDER THE MANIFEST BASED ON GOOGLE'S AI!
          if (sequence.isNotEmpty && sequence.length == activeOrders.length) {
            // Re-sort the database orders to physically match Google's route
            activeOrders = sequence.map((index) => activeOrders[index]).toList();
          }
        } catch (e) {
          debugPrint('Routing API Error: $e');
        }

        // 5. NOW BUILD MARKERS FROM THE AI-SORTED LIST
        Set<Marker> markers = {
          Marker(
            markerId: const MarkerId('station'), 
            position: _stationLocation, 
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue), 
            infoWindow: const InfoWindow(title: 'Origin (Water Station)')
          )
        };

        for (var i = 0; i < activeOrders.length; i++) {
          final o = activeOrders[i];
          final lat = double.parse(o['lat'].toString());
          final lng = double.parse(o['lng'].toString());
          
          markers.add(
            Marker(
              markerId: MarkerId('order_${o['id']}'),
              position: LatLng(lat, lng),
              // Index 0 is GUARANTEED to be the fastest first stop now
              icon: BitmapDescriptor.defaultMarkerWithHue(i == 0 ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(title: i == 0 ? 'Current Dropoff' : 'Next in Queue', snippet: '${o['jugs_ordered']} Jugs'),
            ),
          );
        }

        final currentOrder = activeOrders.first;
        
        // 6. SECURITY CHECK & DETAILS FETCH
        final orderDetails = await supabase
            .from('orders')
            .select('total_amount, user_profiles(full_name)')
            .eq('id', currentOrder['id'])
            .eq('station_id', myBossStationId) 
            .maybeSingle();

        if (mounted) {
          setState(() {
            _allDropoffMarkers = markers;
            _polylines = newPolylines; 
            _currentActiveOrder = currentOrder;
            _destination = LatLng(
              double.parse(currentOrder['lat'].toString()),
              double.parse(currentOrder['lng'].toString()),
            );
            _totalAmount = double.parse((orderDetails?['total_amount'] ?? 0).toString());
            _customerName = orderDetails?['user_profiles']?['full_name'] ?? 'Water Customer';
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentActiveOrder = null;
            _allDropoffMarkers = {};
            _polylines = {};
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Driver Fetch Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _completeDelivery() async {
    if (_currentActiveOrder == null) return;

    setState(() => _isLoading = true);
    try {
      await supabase
          .from('orders')
          .update({'status': 'done'})
          .eq('id', _currentActiveOrder!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery Completed! 🎉'), backgroundColor: Colors.green)
        );
        // Instantly refreshes and calculates the route to the NEXT closest house!
        _fetchActiveDelivery(); 
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey.shade900,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchActiveDelivery, tooltip: 'Refresh Queue'),
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _signOut, tooltip: 'Sign Out'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentActiveOrder == null
              ? _buildEmptyState()
              : Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _destination == null
                          ? const Center(child: Text('Map loading...'))
                          : GoogleMap(
                              // Safely centers on the Red Pin without crashing the controller
                              initialCameraPosition: CameraPosition(target: _destination!, zoom: 15.0),
                              markers: _allDropoffMarkers,
                              polylines: _polylines,
                              onMapCreated: (controller) => _mapController = controller,
                              myLocationEnabled: true, 
                              myLocationButtonEnabled: true,
                            ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -5))],
                        ),
                        child: _buildActiveDeliveryCard(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('No active deliveries right now.', style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('Waiting for the merchant to assign an order...', style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActiveDeliveryCard() {
    final shortId = _currentActiveOrder!['id'].toString().substring(0, 6).toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #$shortId', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text('Deliver to: $_customerName', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20)),
                child: const Text('ACTIVE', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Divider(height: 32, thickness: 1),
          _buildDetailRow(Icons.water_drop, 'Payload:', '${_currentActiveOrder!['jugs_ordered']} Jugs'),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.payments, 'Collect:', '₱${_totalAmount.toStringAsFixed(2)}'),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _completeDelivery,
            icon: const Icon(Icons.check_circle, size: 28, color: Colors.white),
            label: const Text('COMPLETE DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 15, color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}