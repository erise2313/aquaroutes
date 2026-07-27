import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/location_service.dart';
import '../../services/route_optimization.dart';
import '../auth/login_screen.dart';
import 'driver_profile_screen.dart';

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
  String _customerPhone = ""; 
  String _stationPhone = ""; 
  String _stationName = "Water Station";
  double _totalAmount = 0.0;
  LatLng? _destination;
  GoogleMapController? _mapController;
  
  Set<Marker> _allDropoffMarkers = {}; 
  Set<Polyline> _polylines = {}; 

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

      // 1. Fetch driver profile & assigned station ID
      final profile = await supabase
          .from('user_profiles')
          .select('assigned_station_id')
          .eq('id', userId)
          .maybeSingle();

      if (profile == null || profile['assigned_station_id'] == null) {
        throw Exception("You are not linked to a water station.");
      }
      final myBossStationId = profile['assigned_station_id'];

      // 2. Fetch station owner details (Safely handling List vs Map join response)
      final stationData = await supabase
          .from('water_stations')
          .select('station_name, owner_id, user_profiles(phone_number)')
          .eq('id', myBossStationId)
          .maybeSingle();

      if (stationData != null) {
        _stationName = stationData['station_name'] ?? 'Water Station';
        
        // 🛡️ SAFE EXTRACTOR: Handles if Supabase returns user_profiles as a List or a Map
        final rawProfile = stationData['user_profiles'];
        if (rawProfile is List && rawProfile.isNotEmpty) {
          _stationPhone = rawProfile.first['phone_number']?.toString() ?? '';
        } else if (rawProfile is Map) {
          _stationPhone = rawProfile['phone_number']?.toString() ?? '';
        }
      }

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
        
        try {
          final result = await _routeService.calculateDriverManifest(
            {"lat": _stationLocation.latitude, "lng": _stationLocation.longitude},
            customerLocationsForRouting,
          );
          
          final String poly = result['polyline'];
          final rawSequence = result['sequence'];

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

          if (rawSequence != null && rawSequence is List && rawSequence.isNotEmpty) {
            try {
              List<int> sequence = rawSequence.map((idx) => int.parse(idx.toString())).toList();
              if (sequence.length == activeOrders.length) {
                bool validBounds = sequence.every((idx) => idx >= 0 && idx < activeOrders.length);
                if (validBounds) {
                  activeOrders = sequence.map((index) => activeOrders[index]).toList();
                }
              }
            } catch (err) {
              debugPrint("Sequence reordering skipped safely: $err");
            }
          }
        } catch (e) {
          debugPrint('Routing API Error: $e');
        }

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
              icon: BitmapDescriptor.defaultMarkerWithHue(i == 0 ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(title: i == 0 ? 'Current Dropoff' : 'Next in Queue', snippet: '${o['jugs_ordered']} Jugs'),
            ),
          );
        }

        final currentOrder = activeOrders.first;
        
        final orderDetails = await supabase
            .from('orders')
            .select('total_amount, user_profiles(full_name, phone_number)')
            .eq('id', currentOrder['id'])
            .eq('station_id', myBossStationId) 
            .maybeSingle();

        // 🛡️ SAFE EXTRACTOR for customer profile join
        String custName = 'Water Customer';
        String custPhone = '';
        if (orderDetails != null) {
          final rawCustProfile = orderDetails['user_profiles'];
          if (rawCustProfile is List && rawCustProfile.isNotEmpty) {
            custName = rawCustProfile.first['full_name']?.toString() ?? 'Water Customer';
            custPhone = rawCustProfile.first['phone_number']?.toString() ?? '';
          } else if (rawCustProfile is Map) {
            custName = rawCustProfile['full_name']?.toString() ?? 'Water Customer';
            custPhone = rawCustProfile['phone_number']?.toString() ?? '';
          }
        }

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
            _customerName = custName;
            _customerPhone = custPhone;
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

  Future<void> _makePhoneCall(String phoneNumber, String targetName) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No phone number available for $targetName.')),
      );
      return;
    }
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint('Could not launch phone dialer for $phoneNumber');
    }
  }

  void _showCompletionDialog() {
    if (_currentActiveOrder == null) return;

    final TextEditingController emptyJugsController = TextEditingController(text: '1');
    bool paymentCollected = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete Delivery & Return'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Log the returned empty jugs and confirm cash collection before finalizing.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emptyJugsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Empty Jugs Collected',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Cash Payment Collected'),
                value: paymentCollected,
                onChanged: (val) {
                  setDialogState(() {
                    paymentCollected = val ?? true;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                final int emptyJugs = int.tryParse(emptyJugsController.text) ?? 0;
                Navigator.pop(context);
                _finalizeDelivery(emptyJugs, paymentCollected);
              },
              child: const Text('Confirm & Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizeDelivery(int emptyJugsCollected, bool paymentCollected) async {
    setState(() => _isLoading = true);
    try {
      await supabase
          .from('orders')
          .update({
            'status': 'done',
            'empty_jugs_returned': emptyJugsCollected,
            'payment_collected': paymentCollected,
          })
          .eq('id', _currentActiveOrder!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delivery Completed! 🎉'), 
            backgroundColor: Colors.green,
          ),
        );
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
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            tooltip: 'Driver Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DriverProfileScreen()),
              );
            },
          ),
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
                  Row(
                    children: [
                      Text('Deliver to: $_customerName', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _makePhoneCall(_customerPhone, 'Customer'),
                        child: const Icon(Icons.phone, size: 18, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20)),
                child: const Text('ACTIVE', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          Row(
            children: [
              Icon(Icons.store, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 8),
              Text('Station: $_stationName', style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _makePhoneCall(_stationPhone, 'Water Station'),
                icon: const Icon(Icons.phone, size: 16, color: Colors.green),
                label: const Text('Call Station', style: TextStyle(fontSize: 12, color: Colors.green)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.water_drop, 'Payload:', '${_currentActiveOrder!['jugs_ordered']} Jugs'),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.payments, 'Collect:', '₱${_totalAmount.toStringAsFixed(2)}'),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showCompletionDialog,
            icon: const Icon(Icons.check_circle, size: 28, color: Colors.white),
            label: const Text('COMPLETE DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 16),
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