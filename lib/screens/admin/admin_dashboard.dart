import 'package:flutter/material.dart';
import 'settings_screen.dart'; // Ensure these files exist
import 'driver_management.dart'; // Ensure these files exist
import 'order_detail_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Station Admin"),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: "Manage Drivers",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DriverManagement()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "System Config",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _buildStatCard(
                  "Total Orders",
                  "124",
                  Icons.shopping_bag,
                  Colors.blue,
                ),
                _buildStatCard(
                  "Active",
                  "8",
                  Icons.local_shipping,
                  Colors.orange,
                ),
                _buildStatCard(
                  "Pending",
                  "5",
                  Icons.pending_actions,
                  Colors.red,
                ),
                _buildStatCard(
                  "Completed",
                  "111",
                  Icons.check_circle,
                  Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Recent Activity",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 10),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (ctx, i) => const Divider(),
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.water_drop)),
                title: Text("Order #00${index + 1}"),
                subtitle: const Text("Delivered at 10:30 AM"),
                trailing: const Text("₱150.00"),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        OrderDetailScreen(orderId: "00${index + 1}"),
                  ), //BACKEND NEED YAAAAAAAAa
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 3,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
