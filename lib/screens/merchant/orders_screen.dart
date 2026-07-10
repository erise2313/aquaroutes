import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  // 1. Establish the live WebSockets connection to the 'orders' table
  final _ordersStream = Supabase.instance.client
      .from('orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false); // Newest orders at the top

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Live Order Pipeline"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "New"),
              Tab(text: "Active"),
              Tab(text: "Done"),
            ],
          ),
        ),
        // 2. The StreamBuilder listens for database changes automatically
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _ordersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Database Error: ${snapshot.error}'));
            }

            final allOrders = snapshot.data ?? [];

            // Filter the master list into the three tab categories
            final newOrders = allOrders
                .where((o) => o['status'] == 'pending')
                .toList();
            final activeOrders = allOrders
                .where((o) => o['status'] == 'active')
                .toList();
            final doneOrders = allOrders
                .where((o) => o['status'] == 'completed')
                .toList();

            return TabBarView(
              children: [
                _buildOrderList(newOrders, "pending"),
                _buildOrderList(activeOrders, "active"),
                _buildOrderList(doneOrders, "completed"),
              ],
            );
          },
        ),
      ),
    );
  }

  // 3. Dynamic List Builder
  Widget _buildOrderList(List<Map<String, dynamic>> orders, String statusType) {
    if (orders.isEmpty) {
      return const Center(
        child: Text(
          "No orders in this queue.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.water_drop, color: Colors.white),
            ),
            // Slice the UUID so it looks like a clean order number
            title: Text(
              "Order #${order['id'].toString().substring(0, 6).toUpperCase()}",
            ),
            subtitle: Text(
              "Jugs: ${order['jug_count']} | Total: ₱${order['total_price']}",
            ),
            trailing: _buildActionIcon(order['id'], statusType),
          ),
        );
      },
    );
  }

  // 4. Admin Controls to update the database
  Widget _buildActionIcon(String orderId, String currentStatus) {
    if (currentStatus == 'pending') {
      return IconButton(
        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
        tooltip: "Assign to Driver",
        onPressed: () => _updateOrderStatus(orderId, 'active'),
      );
    } else if (currentStatus == 'active') {
      return IconButton(
        icon: const Icon(Icons.done_all, color: Colors.blue),
        tooltip: "Mark as Completed",
        onPressed: () => _updateOrderStatus(orderId, 'completed'),
      );
    }
    return const Icon(Icons.check, color: Colors.grey); // Done state
  }

  // 5. The Supabase Update Function
  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await Supabase.instance.client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error updating order: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
