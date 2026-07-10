import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverManagement extends StatefulWidget {
  const DriverManagement({super.key});

  @override
  State<DriverManagement> createState() => _DriverManagementState();
}

class _DriverManagementState extends State<DriverManagement> {
  final supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _vehicleController = TextEditingController();
  bool _isLoading = false;

  // 1. Database Write: Creating the Driver Credential
  Future<void> _addDriver() async {
    if (_nameController.text.isEmpty || _vehicleController.text.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final merchantId = supabase.auth.currentUser?.id;
      if (merchantId == null) throw Exception("Merchant not logged in.");

      await supabase.from('drivers').insert({
        'merchant_id': merchantId,
        'full_name': _nameController.text.trim(),
        'vehicle_details': _vehicleController.text.trim(),
      });

      if (mounted) {
        Navigator.pop(context); // Close the dialog
        _nameController.clear();
        _vehicleController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Driver successfully added to fleet!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Database Error: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. The Form UI
  void _showAddDriverDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Register New Driver"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Driver Full Name",
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _vehicleController,
              decoration: const InputDecoration(
                labelText: "Vehicle (e.g., Tricycle - 001)",
                prefixIcon: Icon(Icons.two_wheeler),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _addDriver,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text(
              "Save Driver",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Database Read: Deleting a Driver
  Future<void> _deleteDriver(String driverId) async {
    try {
      await supabase.from('drivers').delete().eq('id', driverId);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error removing driver: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 4. Live Stream Connection to the Database
    final merchantId = supabase.auth.currentUser?.id;
    final driverStream = supabase
        .from('drivers')
        .stream(primaryKey: ['id'])
        .eq('merchant_id', merchantId ?? '')
        .order('created_at');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Manage Fleet",
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: driverStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Connection Error: ${snapshot.error}"));
          }

          final drivers = snapshot.data ?? [];

          if (drivers.isEmpty) {
            return const Center(
              child: Text(
                "No drivers registered yet.",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade50,
                    child: const Icon(Icons.person, color: Colors.blueAccent),
                  ),
                  title: Text(
                    driver['full_name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Vehicle: ${driver['vehicle_details']}"),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _deleteDriver(driver['id']),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDriverDialog,
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Driver", style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
