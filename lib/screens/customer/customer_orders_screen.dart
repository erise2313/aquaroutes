import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // Make sure this is imported for date formatting

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<dynamic> _ongoingOrders = [];
  List<dynamic> _pastOrders = [];

  @override
  void initState() {
    super.initState();
    _fetchMyOrders();
  }

  Future<void> _fetchMyOrders() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      
      // Fetch orders and use Supabase's implicit join to get the station name
      final response = await supabase
          .from('orders')
          .select('id, status, total_amount, created_at, water_stations(station_name)')
          .eq('customer_id', userId)
          .order('created_at', ascending: false);

      final ongoing = [];
      final past = [];

      for (var order in response) {
        final status = order['status']?.toString().toLowerCase() ?? '';
        // Route to the correct tab based on status
        if (status == 'completed' || status == 'cancelled' || status == 'done') {
          past.add(order);
        } else {
          ongoing.add(order);
        }
      }

      if (mounted) {
        setState(() {
          _ongoingOrders = ongoing;
          _pastOrders = past;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading orders: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          backgroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(text: 'Ongoing Orders'),
              Tab(text: 'Past Orders'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildOrderList(_ongoingOrders, isOngoing: true),
                  _buildOrderList(_pastOrders, isOngoing: false),
                ],
              ),
      ),
    );
  }

  Widget _buildOrderList(List<dynamic> orders, {required bool isOngoing}) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          isOngoing ? 'No ongoing orders right now.' : 'No past orders yet.',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMyOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          
          // Truncate the UUID to make it look like a clean Order Number (e.g. Order #A1B2C3D4)
          final shortId = order['id'].toString().substring(0, 8).toUpperCase();
          final status = order['status'].toString().toUpperCase();
          
          // Extract the joined station name
          final stationData = order['water_stations'];
          final stationName = stationData != null ? stationData['station_name'] : 'Unknown Station';
          
          final total = order['total_amount'] != null ? '₱${order['total_amount']}' : 'TBD';
          
          // Format the date nicely
          DateTime date = DateTime.parse(order['created_at']);
          String formattedDate = DateFormat('MMM d, yyyy - h:mm a').format(date);

          return Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Order #$shortId',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        total,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Status: $status',
                    style: TextStyle(
                      color: isOngoing ? Colors.orange.shade700 : Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.storefront, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          stationName,
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        formattedDate,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}