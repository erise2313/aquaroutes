import 'package:flutter/material.dart';
import 'settings_screen.dart';       // Ensure these files exist
import 'driver_management.dart';    // Ensure these files exist

class AdminDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Station Admin"),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: Icon(Icons.people),
            tooltip: "Manage Drivers",
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => DriverManagement())),
          ),
          IconButton(
            icon: Icon(Icons.settings),
            tooltip: "System Config",
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SettingsScreen())),
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
              physics: NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _buildStatCard("Total Orders", "124", Icons.shopping_bag, Colors.blue),
                _buildStatCard("Active", "8", Icons.local_shipping, Colors.orange),
                _buildStatCard("Pending", "5", Icons.pending_actions, Colors.red),
                _buildStatCard("Completed", "111", Icons.check_circle, Colors.green),
              ],
            ),
            
            SizedBox(height: 24),
            
            Align(
              alignment: Alignment.centerLeft,
              child: Text("Recent Activity", 
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            
            SizedBox(height: 10),
            
            ListView.separated(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (ctx, i) => Divider(),
              itemBuilder: (context, index) => ListTile(
                leading: CircleAvatar(child: Icon(Icons.water_drop)),
                title: Text("Order #00${index + 1}"),
                subtitle: Text("Delivered at 10:30 AM"),
                trailing: Text("₱150.00"),
                onTap: () => Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: "00${index + 1}")) //BACKEND NEED YAAAAAAAAa
                ),
              )
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}