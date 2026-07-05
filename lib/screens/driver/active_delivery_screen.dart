import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ActiveDeliveryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: LatLng(14.3498, 120.8936), zoom: 15),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text("Next Stop: Customer A", style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 10),
                    LinearProgressIndicator(value: 0.75), // Visualization of Payload
                    SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () {
                        // This button triggers the weight decrement
                      },
                      child: Text("Mark as Delivered"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}