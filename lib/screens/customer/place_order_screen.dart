import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaceOrderScreen extends StatefulWidget {
  const PlaceOrderScreen({super.key});

  @override
  State<PlaceOrderScreen> createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _jugCountController = TextEditingController();
  
  final LatLng _initialCenter = const LatLng(14.3152, 120.9156);
  
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  
  bool _isLoading = false;
  bool _isFetchingStations = true;
  
  List<Map<String, dynamic>> _availableStations = [];
  String? _selectedStationId;
  
  // Dynamic Pricing Variables
  double _currentPricePerJug = 0.0;
  double _currentDeliveryFee = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWaterStations();
  }

  Future<void> _fetchWaterStations() async {
    try {
      // Fetching the dynamic prices alongside the station name!
      final response = await supabase
          .from('water_stations')
          .select('id, station_name, price_per_jug, delivery_fee');
          
      if (mounted) {
        setState(() {
          _availableStations = List<Map<String, dynamic>>.from(response);
          if (_availableStations.isNotEmpty) {
            _selectedStationId = _availableStations.first['id'].toString();
            _updateDisplayedPrices(_selectedStationId!);
          }
          _isFetchingStations = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching stations: $e");
      if (mounted) setState(() => _isFetchingStations = false);
    }
  }

  // Updates the pricing UI when a new station is selected
  void _updateDisplayedPrices(String stationId) {
    final station = _availableStations.firstWhere((s) => s['id'].toString() == stationId);
    setState(() {
      _currentPricePerJug = double.tryParse(station['price_per_jug']?.toString() ?? '40.0') ?? 40.0;
      _currentDeliveryFee = double.tryParse(station['delivery_fee']?.toString() ?? '20.0') ?? 20.0;
    });
  }

  void _onMapTapped(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _markers = {
        Marker(
          markerId: const MarkerId('customer_home'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'My Delivery Address'),
        )
      };
    });
  }

  Future<void> _submitOrder() async {
    if (_selectedStationId == null || _selectedLocation == null || _jugCountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete all fields and drop a pin!')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final customerId = supabase.auth.currentUser!.id;
      final int jugs = int.parse(_jugCountController.text);

      // --- 🧮 DYNAMIC FINANCIAL ENGINE ---
      final double calculatedSubtotal = jugs * _currentPricePerJug;
      final double calculatedTotal = calculatedSubtotal + _currentDeliveryFee;

      await supabase.from('orders').insert({
        'station_id': _selectedStationId,
        'customer_id': customerId,
        'delivery_location': 'POINT(${_selectedLocation!.longitude} ${_selectedLocation!.latitude})', 
        'jugs_ordered': jugs,
        'status': 'pending',
        'payment_method': 'cash', 
        'subtotal': calculatedSubtotal,
        'delivery_fee': _currentDeliveryFee,
        'total_amount': calculatedTotal,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order Placed Successfully! 🎉')),
        );
        setState(() {
          _markers.clear();
          _selectedLocation = null;
          _jugCountController.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place Water Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade700,
      ),
      body: _isFetchingStations 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: _initialCenter, zoom: 14.0),
                        markers: _markers,
                        onTap: _onMapTapped,
                      ),
                      Positioned(
                        top: 10, left: 10, right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.white.withOpacity(0.9),
                          child: const Text('📍 Tap the map to set your delivery address', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
                
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedStationId,
                          decoration: const InputDecoration(labelText: '1. Select Water Station', border: OutlineInputBorder(), prefixIcon: Icon(Icons.storefront)),
                          items: _availableStations.map((station) {
                            return DropdownMenuItem<String>(
                              value: station['id'].toString(),
                              child: Text(station['station_name'].toString()),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStationId = val);
                              _updateDisplayedPrices(val); // Update pricing when station changes
                            }
                          },
                        ),
                        
                        // Show the dynamic pricing to the user
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                          child: Text(
                            'Rates: ₱${_currentPricePerJug.toStringAsFixed(2)}/jug | ₱${_currentDeliveryFee.toStringAsFixed(2)} delivery fee',
                            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                        ),
                        
                        const SizedBox(height: 8),
                        
                        TextField(
                          controller: _jugCountController,
                          decoration: const InputDecoration(labelText: '2. Number of Jugs', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop)),
                          keyboardType: TextInputType.number,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submitOrder,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(vertical: 20)),
                          child: _isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('PLACE ORDER', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}