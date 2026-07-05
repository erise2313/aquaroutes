import 'package:flutter/material.dart';

class DriverManagement extends StatelessWidget {
  final List<String> drivers = ["Juan Dela Cruz", "Pedro Penduko"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Manage Drivers")),
      body: ListView.builder(
        itemCount: drivers.length,
        itemBuilder: (context, index) => ListTile(
          leading: CircleAvatar(child: Icon(Icons.person)),
          title: Text(drivers[index]),
          subtitle: Text("Vehicle: Tricycle - 001"),
          trailing: IconButton(icon: Icon(Icons.edit), onPressed: () {}),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {
          // Add driver logic
        },
      ),
    );
  }
}