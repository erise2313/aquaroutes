import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fleet Management")),
      // We join user_profiles with driver_states to get location/speed
      body: StreamBuilder(
        stream: _supabase.from('user_profiles')
            .stream(primaryKey: ['id'])
            .eq('role', 'driver'), 
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final drivers = snapshot.data!;
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

  Widget _buildDriverCard(Map<String, dynamic> driver) {
    // Logic: Speed < 0.5 m/s = Idling
    final double speed = (driver['current_speed'] ?? 0.0).toDouble();
    final bool isIdling = speed < 0.5;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(Icons.directions_car, color: isIdling ? Colors.orange : Colors.green),
        title: Text(driver['full_name'] ?? 'Driver'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Plate: ${driver['vehicle_plate'] ?? 'N/A'}"),
            Text("Capacity: ${driver['jug_capacity'] ?? 0} jugs"),
          ],
        ),
        trailing: isIdling 
            ? const Icon(Icons.warning_amber, color: Colors.orange) 
            : const Icon(Icons.check_circle, color: Colors.green),
        onTap: () => _showEditDialog(driver),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> driver) {
    final plateController = TextEditingController(text: driver['vehicle_plate']);
    final capController = TextEditingController(text: driver['jug_capacity']?.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Configure ${driver['full_name']}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: plateController, decoration: const InputDecoration(labelText: "Plate Number")),
            TextField(controller: capController, decoration: const InputDecoration(labelText: "Capacity (Jugs)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _supabase.from('user_profiles').update({
                'vehicle_plate': plateController.text,
                'jug_capacity': int.tryParse(capController.text),
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