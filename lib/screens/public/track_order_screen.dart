import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import 'order_tracking_screen.dart';

/// Guest order tracking. No account exists for a guest order, so the phone
/// number doubles as the access credential (lookup_guest_order() RPC,
/// 0008_bulletin.sql, only returns a row when it matches) -- knowing an
/// order ID alone isn't enough to read someone else's delivery details.
/// Also offers a one-tap "use my last order" shortcut from the order id/
/// phone OrderConfirmationScreen persisted locally on this device.
class TrackOrderScreen extends StatefulWidget {
  const TrackOrderScreen({super.key});

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  final _orderService = OrderService(SupabaseService.instance);
  final _formKey = GlobalKey<FormState>();
  final _orderIdController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  GuestOrderStatus? _result;
  String? _lastOrderId;
  String? _lastOrderPhone;

  @override
  void initState() {
    super.initState();
    _loadLastOrder();
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadLastOrder() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastOrderId = prefs.getString('last_guest_order_id');
        _lastOrderPhone = prefs.getString('last_guest_order_phone');
      });
    }
  }

  Future<void> _useLastOrder() async {
    if (_lastOrderId == null || _lastOrderPhone == null) return;
    _orderIdController.text = _lastOrderId!;
    _phoneController.text = _lastOrderPhone!;
    _lookup();
  }

  Future<void> _lookup() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _orderService.lookupGuestOrder(
        orderId: _orderIdController.text.trim(),
        guestPhone: _phoneController.text.trim(),
      );
      setState(() {
        _result = result;
        _error = result == null ? 'No matching order found. Check the order ID and phone number.' : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not look up this order: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track My Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lastOrderId != null) ...[
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _useLastOrder,
                  icon: const Icon(Icons.history),
                  label: const Text('Use my last order on this device'),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _orderIdController,
                decoration: const InputDecoration(labelText: 'Order ID', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your order ID' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number Used at Checkout', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the phone number you ordered with' : null,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _lookup,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Track Order', style: TextStyle(color: Colors.white)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 24),
                _buildResultCard(_result!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(GuestOrderStatus result) {
    final (statusColor, statusLabel) = switch (result.status) {
      OrderStatus.pending => (Colors.orange, 'Pending'),
      OrderStatus.assigned => (Colors.blue, 'Driver Assigned'),
      OrderStatus.active => (Colors.indigo, 'Out for Delivery'),
      OrderStatus.done => (Colors.green, 'Delivered'),
      OrderStatus.cancelled => (Colors.red, 'Cancelled'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(result.stationName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${result.jugsOrdered} jugs of ${result.waterType}'),
            Text('Total: ${formatPeso(result.totalAmount)}'),
            const SizedBox(height: 4),
            Text('Placed ${DateFormat('MMM d, yyyy h:mm a').format(result.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (result.status == OrderStatus.assigned || result.status == OrderStatus.active) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OrderTrackingScreen(
                      orderId: result.id,
                      stationName: result.stationName,
                      status: result.status,
                      guestPhone: _phoneController.text.trim(),
                    ),
                  ),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Track my driver'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
