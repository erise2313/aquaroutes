import 'package:flutter/material.dart';

class PlaceOrderScreen extends StatelessWidget {
  final String stationName;
  PlaceOrderScreen({required this.stationName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(stationName),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Upper Info Module Card
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("Address", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Home - Block 4 Lot 2, General Trias, Cavite", style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 24),
                      Text("Gallons stuff", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("• 3x 5-Gallon Slim Jug (Blue Key)", style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 15),

            // Financial Breakdown Card Block
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildPricingRow("Sub total", "₱120.00"),
                    _buildPricingRow("Delivery fee", "₱30.00"),
                    const Divider(height: 24),
                    _buildPricingRow("Total", "₱150.00", isBold: true),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),

            // Submit Button Action Wrapper
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order Sent Successfully!")));
                Navigator.pop(context);
              },
              child: const Text("Place Order", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingRow(String label, String cost, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isBold ? Colors.black : Colors.grey, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(cost, style: TextStyle(fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}