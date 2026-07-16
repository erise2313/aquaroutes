import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class MerchantOrdersScreen extends StatefulWidget {
  const MerchantOrdersScreen({super.key});

  @override
  State<MerchantOrdersScreen> createState() => _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends State<MerchantOrdersScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<dynamic> _newOrders = [];
  List<dynamic> _activeOrders = [];
  List<dynamic> _doneOrders = [];

  @override
  void initState() {
    super.initState();
    _fetchStationOrders();
  }

  Future<void> _fetchStationOrders() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final stationData = await supabase
          .from('water_stations')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (stationData != null) {
        // Bulletproof query
        final response = await supabase
            .from('orders')
            .select('id, status, jugs_ordered, total_amount, created_at')
            .eq('station_id', stationData['id'])
            .order('created_at', ascending: false);

        final pending = [];
        final active = [];
        final done = [];

        for (var order in response) {
          final status = order['status']?.toString().toLowerCase();
          if (status == 'pending') {
            pending.add(order);
          } else if (status == 'active') {
            active.add(order);
          } else {
            done.add(order); 
          }
        }

        if (mounted) {
          setState(() {
            _newOrders = pending;
            _activeOrders = active;
            _doneOrders = done;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    await supabase.from('orders').update({'status': newStatus}).eq('id', orderId);
    _fetchStationOrders(); 
  }

  // NEW: Delete Order Function
  Future<void> _deleteOrder(String orderId) async {
    // Show a quick loading indicator
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleting order...')));
    
    try {
      await supabase.from('orders').delete().eq('id', orderId);
      _fetchStationOrders(); // Refresh the screen instantly
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order permanently deleted. 🗑️')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live Order Pipeline', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(text: 'New'),
              Tab(text: 'Active'),
              Tab(text: 'Done'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildOrderList(_newOrders, 'pending'),
                  _buildOrderList(_activeOrders, 'active'),
                  _buildOrderList(_doneOrders, 'done'),
                ],
              ),
      ),
    );
  }

  Widget _buildOrderList(List<dynamic> orders, String listType) {
    if (orders.isEmpty) {
      return const Center(child: Text('No orders in this pipeline.', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: _fetchStationOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final shortId = order['id'].toString().substring(0, 6).toUpperCase();
          
          DateTime date = DateTime.parse(order['created_at']);
          String time = DateFormat('h:mm a').format(date);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: const Icon(Icons.water_drop, color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Order #$shortId', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Created at $time', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      // NEW: The Delete Button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteOrder(order['id']),
                        tooltip: 'Delete this test order',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Jugs: ${order['jugs_ordered']} | Total: ₱${order['total_amount']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  
                  if (listType == 'pending') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.grey),
                            onPressed: () => _updateStatus(order['id'], 'cancelled'),
                            child: const Text('REJECT'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () => _updateStatus(order['id'], 'active'),
                            child: const Text('ACCEPT', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    )
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}