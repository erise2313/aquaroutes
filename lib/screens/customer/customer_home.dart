import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aquaroute/screens/customer/place_order_screen.dart'; // Ensure this matches your folder structure

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final supabase = Supabase.instance.client;
  String _customerName = 'Customer';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomerData();
  }

  // Fetch the actual name from user_profiles table
  Future<void> _fetchCustomerData() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final response = await supabase
          .from('user_profiles')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _customerName = response['full_name'] ?? 'Customer';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaRoutes', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.blue.shade700,
        automaticallyImplyLeading: false, 
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome back, $_customerName!',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),
                  
                  // Main Action Card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(Icons.water_drop, size: 60, color: Colors.blue.shade600),
                          const SizedBox(height: 16),
                          const Text(
                            'Need a water refill?',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Drop a pin on your exact location to order directly from your nearest station.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          
                          // Navigation Button to the Place Order Screen
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const PlaceOrderScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'PLACE NEW ORDER',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}