import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SandboxScreen extends StatefulWidget {
  const SandboxScreen({super.key});

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _jugCountController = TextEditingController();
  
  final LatLng _initialCenter = const LatLng(14.3152, 120.9156);
  
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  bool _isLoading = false;

  // Sandbox variables
  String _selectedStatus = 'pending'; // Default status to inject
  double _pricePerJug = 40.0;
  double _deliveryFee = 20.0;

  void _onMapTapped(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _markers = {
        Marker(
          markerId: const MarkerId('sandbox_target'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Sandbox Target Injection'),
        )
      };
    });
  }

  Future<void> injectSandboxOrder() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tap the map to drop a pin first!')),
      );
      return;
    }

    if (_jugCountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a jug count!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Get the current Merchant's Station ID & dynamic prices
      final stationData = await supabase
          .from('water_stations')
          .select('id, price_per_jug, delivery_fee')
          .eq('owner_id', userId)
          .maybeSingle();

      if (stationData == null) throw Exception("No water station found for this merchant!");
      final stationId = stationData['id'];
      
      // Fallback to defaults if null in DB
      _pricePerJug = double.tryParse(stationData['price_per_jug']?.toString() ?? '40.0') ?? 40.0;
      _currentDeliveryFee = double.tryParse(stationData['delivery_fee']?.toString() ?? '20.0') ?? 20.0;

      // 2. Grab a random customer ID to assign to this sandbox order
      final customerData = await supabase
          .from('user_profiles')
          .select('id')
          .eq('role', 'customer')
          .limit(1)
          .maybeSingle();
      
      if (customerData == null) throw Exception("No customers exist in the database!");
      final customerId = customerData['id'];

      // 3. Perform the dynamic math calculation
      final int jugs = int.parse(_jugCountController.text);
      final double calculatedSubtotal = jugs * _pricePerJug;
      final double calculatedTotal = calculatedSubtotal + _deliveryFee;

      // 4. Inject into the Orders table
      await supabase.from('orders').insert({
        'station_id': stationId,
        'customer_id': customerId,
        'delivery_location': 'POINT(${_selectedLocation!.longitude} ${_selectedLocation!.latitude})',
        'jugs_ordered': jugs,
        'status': _selectedStatus, // Can be 'pending' or 'active'
        'payment_method': 'cash', 
        'subtotal': calculatedSubtotal,
        'delivery_fee': _deliveryFee,
        'total_amount': calculatedTotal,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sandbox Order injected as "$_selectedStatus"!')),
        );
        setState(() {
          _markers.clear();
          _selectedLocation = null;
          _jugCountController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Quick helper to convert status to double for price variable safety
  double get _currentDeliveryFee => _deliveryFee;
  set _currentDeliveryFee(double val) => _deliveryFee = val;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DEV SANDBOX', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.red.shade800,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _initialCenter, zoom: 14.0),
              markers: _markers,
              onTap: _onMapTapped,
            ),
          ),
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _selectedLocation == null 
                        ? '1. Tap map to select location'
                        : '1. Target Locked: ${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 15, 
                      fontWeight: FontWeight.bold,
                      color: _selectedLocation == null ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Layout inputs side-by-side to fit nicely
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _jugCountController,
                          decoration: const InputDecoration(
                            labelText: '2. Jug Count', 
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedStatus,
                          decoration: const InputDecoration(
                            labelText: '3. Status',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pending', child: Text('Pending')),
                            DropdownMenuItem(value: 'active', child: Text('Active')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedStatus = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : injectSandboxOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('4. INJECT SANDBOX ORDER', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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