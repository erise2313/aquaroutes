import 'package:flutter/material.dart';
import 'active_delivery_screen.dart';
import 'payload_tracker.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Portal"),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Current Status Header
            Card(
              color: Colors.blue.shade50,
              child: const ListTile(
                leading: Icon(
                  Icons.local_shipping,
                  size: 40,
                  color: Colors.blue,
                ),
                title: Text(
                  "Ready for Route",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("Current Load: 15/20 Jugs"),
              ),
            ),

            const SizedBox(height: 20),

            // Navigation Actions
            _buildActionTile(
              context,
              "Start Active Route",
              "View map and next destination",
              Icons.map,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActiveDeliveryScreen()),
              ),
            ),

            _buildActionTile(
              context,
              "Manage Inventory",
              "Track full jugs and empty returns",
              Icons.inventory,
              Colors.orange,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PayloadTracker()),
              ),
            ),

            _buildActionTile(
              context,
              "Past Deliveries",
              "View your daily delivery log",
              Icons.history,
              Colors.blueGrey,
              () {}, // Link to history screen
            ),
          ],
        ),
      ),
    );
  }

  // Reusable Action Tile for clean UI
  Widget _buildActionTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
