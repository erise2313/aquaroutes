import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _jugWeightController = TextEditingController(text: "19");
  final _velocityLimitController = TextEditingController(text: "20");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("System Configuration")),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Dynamic Payload Math Engine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            TextField(
              controller: _jugWeightController,
              decoration: InputDecoration(labelText: "Weight per 5-Gallon Jug (kg)", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 15),
            TextField(
              controller: _velocityLimitController,
              decoration: InputDecoration(labelText: "Safety Velocity Limit (kph)", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Logic to save to Supabase will go here
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Settings Updated")));
              },
              child: Text("Save Configuration"),
            ),
          ],
        ),
      ),
    );
  }
}