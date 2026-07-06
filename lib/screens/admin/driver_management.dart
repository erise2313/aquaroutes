import 'package:flutter/material.dart';

class DriverManagement extends StatelessWidget {
  final List<String> drivers = ["Juan Dela Cruz", "Pedro Penduko"];

  DriverManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Manage Drivers")),
      body: ListView.builder(
        itemCount: drivers.length,
        itemBuilder: (context, index) => ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(drivers[index]),
          subtitle: const Text("Vehicle: Tricycle - 001"),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          // Add driver logic
        },
      ),
    );
  }
}
