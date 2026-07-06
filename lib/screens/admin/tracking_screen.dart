import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  _TrackingScreenState createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late GoogleMapController mapController;

  // Center the map on General Trias
  final LatLng _center = const LatLng(14.3498, 120.8936);

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Fleet Tracking")),
      body: Column(
        children: [
          // 1. Map View
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 14.0,
              ),
            ),
          ),

          // 2. Driver Telemetry Summary (Real-time data placeholder)
          Container(
            padding: const EdgeInsets.all(16),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.delivery_dining, color: Colors.blue),
                  title: Text("Driver: Juan Dela Cruz"),
                  subtitle: Text("Status: En-Route | Payload: 12/20 jugs"),
                ),
                LinearProgressIndicator(value: 0.6), // Payload math visual
              ],
            ),
          ),
        ],
      ),
    );
  }
}
