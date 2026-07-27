import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  final _supabase = Supabase.instance.client;
  int _idleThresholdMinutes = 5; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Fleet Management & Tracking"),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Set Custom Idle Threshold',
            onPressed: _showIdleThresholdDialog,
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _supabase.from('user_profiles')
            .stream(primaryKey: ['id'])
            .eq('role', 'driver'), 
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final drivers = snapshot.data!;
          
          if (drivers.isEmpty) {
            return const Center(child: Text('No drivers registered yet.'));
          }

          return ListView.builder(
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              return _buildDriverCard(driver);
            },
          );
        },
      ),
    );
  }

  // 📞 Function to launch phone dialer
  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number saved for this driver.')),
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

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    final double speed = (driver['current_speed'] ?? 0.0).toDouble();
    final bool isStationary = speed < 0.5;
    final String phoneNumber = driver['phone_number'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(Icons.directions_car, color: isStationary ? Colors.orange : Colors.green),
        title: Text(driver['full_name'] ?? 'Driver'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Plate: ${driver['vehicle_plate'] ?? 'N/A'}"),
            Text("Phone: ${phoneNumber.isNotEmpty ? phoneNumber : 'No number'}"),
            if (isStationary)
              Text(
                "Stationary (Limit: $_idleThresholdMinutes mins)", 
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 📞 Direct Call Button for the Merchant to reach the driver
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              tooltip: 'Call Driver',
              onPressed: () => _makePhoneCall(phoneNumber),
            ),
            if (isStationary)
              IconButton(
                icon: const Icon(Icons.notifications_active, color: Colors.orange),
                tooltip: 'Send Idle Reminder',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Idle reminder sent to ${driver['full_name']}. 📳'),
                      backgroundColor: Colors.orange.shade700,
                    ),
                  );
                },
              ),
          ],
        ),
        onTap: () => _showEditDialog(driver),
      ),
    );
  }

  void _showIdleThresholdDialog() {
    final controller = TextEditingController(text: _idleThresholdMinutes.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Configure Idle Timer Limit"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Set how long a driver can remain stationary before an idle reminder alert is enabled:"),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Threshold (Minutes)"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _idleThresholdMinutes = int.tryParse(controller.text) ?? 5;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Idle limit updated to $_idleThresholdMinutes minutes.')),
              );
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> driver) {
    final plateController = TextEditingController(text: driver['vehicle_plate']);
    final capController = TextEditingController(text: driver['jug_capacity']?.toString());
    final phoneController = TextEditingController(text: driver['phone_number']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Configure ${driver['full_name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: plateController, decoration: const InputDecoration(labelText: "Plate Number")),
            TextField(controller: capController, decoration: const InputDecoration(labelText: "Capacity (Jugs)")),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: "Phone Number")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _supabase.from('user_profiles').update({
                'vehicle_plate': plateController.text,
                'jug_capacity': int.tryParse(capController.text),
                'phone_number': phoneController.text.trim(),
              }).eq('id', driver['id']);
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}