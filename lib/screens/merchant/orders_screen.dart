import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  List<dynamic> _availableDrivers = [];

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
  }

  void _setupRealtimeSubscription() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      final stationData = await supabase
          .from('water_stations')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (stationData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final stationId = stationData['id'];

      final driversResponse = await supabase
          .from('user_profiles')
          .select('id, full_name, vehicle_plate, phone_number')
          .eq('role', 'driver')
          .eq('assigned_station_id', stationId);

      _availableDrivers = driversResponse;

      // Realtime orders stream with joined customer profile phone numbers
      supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('station_id', stationId)
          .order('created_at', ascending: false)
          .listen((data) async {
            // Fetch associated customer phone numbers for the active list
            final pending = [];
            final active = [];
            final done = [];

            for (var order in data) {
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
          });
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
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

  Future<void> _updateStatus(String orderId, String newStatus) async {
    await supabase.from('orders').update({'status': newStatus}).eq('id', orderId);
  }

  Future<void> _assignDriver(String orderId, String driverId) async {
    try {
      await supabase.from('orders').update({
        'driver_id': driverId,
        'status': 'active'
      }).eq('id', orderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver successfully assigned to order! 🚚'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error assigning driver: $e')));
      }
    }
  }

  void _showAssignDriverDialog(String orderId) {
    if (_availableDrivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No drivers found. Add drivers in Fleet Management first!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Driver to Order'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _availableDrivers.length,
            itemBuilder: (context, index) {
              final driver = _availableDrivers[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(driver['full_name'] ?? 'Unnamed Driver'),
                subtitle: Text('Plate: ${driver['vehicle_plate'] ?? 'N/A'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.phone, color: Colors.green),
                  onPressed: () => _makePhoneCall(driver['phone_number'] ?? ''),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _assignDriver(orderId, driver['id']);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteOrder(String orderId) async {
    try {
      await supabase.from('orders').delete().eq('id', orderId);
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
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.blue),
              tooltip: 'Refresh Orders',
              onPressed: () => _setupRealtimeSubscription(),
            ),
          ],
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
      onRefresh: () async => _setupRealtimeSubscription(),
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteOrder(order['id']),
                        tooltip: 'Delete test order',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Jugs: ${order['jugs_ordered']} | Total: ₱${order['total_amount']}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  
                  // If it's active, show call customer action for the merchant
                  if (listType == 'active') ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            // Extract or pass customer phone number linked to order
                            String customerPhone = order['customer_phone'] ?? '';
                            _makePhoneCall(customerPhone);
                          },
                          icon: const Icon(Icons.phone, size: 16, color: Colors.green),
                          label: const Text('Call Customer', style: TextStyle(color: Colors.green)),
                        ),
                      ],
                    ),
                  ],

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
                            onPressed: () => _showAssignDriverDialog(order['id']),
                            child: const Text('ASSIGN & ACCEPT', style: TextStyle(color: Colors.white)),
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