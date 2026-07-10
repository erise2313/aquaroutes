import 'package:flutter/material.dart';

class PayloadTracker extends StatefulWidget {
  const PayloadTracker({super.key});

  @override
  State<PayloadTracker> createState() => _PayloadTrackerState();
}

class _PayloadTrackerState extends State<PayloadTracker> {
  int currentLoad = 15; // Current full jugs on vehicle
  int emptyJugsCollected = 0; // Tracking returns

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Inventory Management")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatCard(
              "Current Full Load",
              "$currentLoad / 20",
              Colors.blue,
            ),
            const SizedBox(height: 20),
            _buildStatCard(
              "Empty Jugs Collected",
              "$emptyJugsCollected",
              Colors.green,
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  onPressed: () => setState(() => emptyJugsCollected++),
                  child: const Icon(Icons.add),
                ),
                const Text(
                  "Scan/Update Returns",
                  style: TextStyle(fontSize: 16),
                ),
                FloatingActionButton(
                  onPressed: () => setState(() => emptyJugsCollected--),
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 4,
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
