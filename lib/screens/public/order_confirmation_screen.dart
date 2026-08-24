import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/formatters.dart';
import '../auth/auth_gate.dart';

/// Post-submit confirmation for a guest quick-order. Persists the order id
/// + phone locally (SharedPreferences) so TrackOrderScreen can offer "use my
/// last order" without requiring the guest to remember/retype anything --
/// there's still no account/session, so this is only a same-device
/// convenience, not a durable order history.
class OrderConfirmationScreen extends StatefulWidget {
  const OrderConfirmationScreen({
    super.key,
    required this.orderId,
    required this.stationName,
    required this.totalAmount,
    required this.guestPhone,
  });

  final String orderId;
  final String stationName;
  final double totalAmount;
  final String guestPhone;

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  @override
  void initState() {
    super.initState();
    _persistLastOrder();
  }

  Future<void> _persistLastOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_guest_order_id', widget.orderId);
    await prefs.setString('last_guest_order_phone', widget.guestPhone);
  }

  @override
  Widget build(BuildContext context) {
    final shortId = widget.orderId.substring(0, 6).toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Order Confirmed')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 72),
              const SizedBox(height: 16),
              Text('Order #$shortId placed!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${widget.stationName} has received your order.', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Total due on delivery: ${formatPeso(widget.totalAmount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthGate()),
                  (route) => false,
                ),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
