import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, int> calculateOrderCounts(List<Map<String, dynamic>> orders) {
  final pending = orders.where((o) => o['status'] == 'pending').length;
  final active = orders.where((o) => o['status'] == 'active').length;
  final done = orders
      .where((o) => o['status'] == 'completed' || o['status'] == 'done')
      .length;

  return {'pending': pending, 'active': active, 'done': done};
}

class MerchantDashboard extends StatefulWidget {
  const MerchantDashboard({super.key});

  @override
  State<MerchantDashboard> createState() => _MerchantDashboardState();
}

class _MerchantDashboardState extends State<MerchantDashboard> {
  final supabase = Supabase.instance.client;
  String _stationName = '';
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadStationName();
  }

  Future<void> _loadStationName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() {});
        }
        return;
      }

      final profile = await supabase
          .from('user_profiles')
          .select('business_name')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _stationName = (profile?['business_name'] as String?)?.trim() ?? '';
        });
      }
    } catch (e) {
      debugPrint('Failed to load station name: $e');
      if (mounted) {
        setState(() {
          _stationName = '';
        });
      }
    }
  }

  Stream<List<Map<String, dynamic>>> get _ordersStream {
    if (_stationName.isEmpty) {
      return const Stream.empty();
    }

    return supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('station_name', _stationName)
        .order('created_at', ascending: false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? [];
        final counts = calculateOrderCounts(orders);
        final pending = counts['pending'] ?? 0;
        final active = counts['active'] ?? 0;
        final done = counts['done'] ?? 0;

        final filteredOrders = _selectedStatus == 'all'
            ? orders
            : orders.where((order) {
                final status =
                    (order['status'] as String?)?.toLowerCase() ?? '';
                if (_selectedStatus == 'done') {
                  return status == 'completed' || status == 'done';
                }
                return status == _selectedStatus;
              }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Merchant Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () {},
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live order overview',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedStatus = 'pending'),
                        child: _buildStatCard(
                          context,
                          'Pending',
                          pending.toString(),
                          Colors.red.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedStatus = 'active'),
                        child: _buildStatCard(
                          context,
                          'Active',
                          active.toString(),
                          Colors.orange.shade400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedStatus = 'done'),
                        child: _buildStatCard(
                          context,
                          'Done',
                          done.toString(),
                          Colors.green.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      _selectedStatus == 'all'
                          ? 'Orders currently in the system'
                          : 'Showing ${_selectedStatus.toUpperCase()} orders',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (_selectedStatus != 'all')
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedStatus = 'all'),
                        child: const Text('Show all'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filteredOrders.isEmpty
                      ? const Center(
                          child: Text(
                            'No orders yet for this station.\nCustomers will appear here when they place an order.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = filteredOrders[index];
                            final status =
                                order['status']?.toString() ?? 'unknown';
                            final id = order['id']?.toString() ?? 'unknown';
                            final shortId = id.length > 6
                                ? id.substring(0, 6).toUpperCase()
                                : id.toUpperCase();

                            return Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.water_drop_outlined,
                                  color: Colors.blue,
                                ),
                                title: Text('Order #$shortId'),
                                subtitle: Text(
                                  'Status: $status • Jugs: ${order['jug_count'] ?? 0}',
                                ),
                                trailing: Chip(label: Text(status)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
