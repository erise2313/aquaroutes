import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/order.dart';
import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/error_state.dart';
import '../../widgets/star_rating.dart';
import 'order_tracking_screen.dart';

/// Authenticated customer's persistent order history -- the real fix for
/// "order tracking is device-local only": orders.customer_profile_id +
/// orders_customer_read RLS (0009_rls.sql) already scope this correctly,
/// this screen just reads it. Unlike TrackOrderScreen (phone-verified guest
/// lookup, one order at a time), this is a full list, always available
/// across devices since it's tied to the account, not local storage.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final _supabase = Supabase.instance.client;
  final _reviewService = ReviewService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser!.id;
      final rows = await _supabase
          .from('orders')
          .select('id, station_id, status, jugs_ordered, water_type, total_amount, created_at, water_stations(station_name)')
          .eq('customer_profile_id', userId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your orders: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _orders.isEmpty
          ? const Center(child: Text('No orders yet.', style: TextStyle(color: Colors.grey)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
              ),
            ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = orderStatusFromString(order['status'] as String? ?? 'pending');
    final stationName = (order['water_stations']?['station_name'] as String?) ?? 'Unknown Station';
    final createdAt = DateTime.parse(order['created_at'] as String);
    final totalAmount = (order['total_amount'] as num).toDouble();

    final (statusColor, statusLabel) = switch (status) {
      OrderStatus.pending => (Colors.orange, 'Pending'),
      OrderStatus.assigned => (Colors.blue, 'Driver Assigned'),
      OrderStatus.active => (Colors.indigo, 'Out for Delivery'),
      OrderStatus.done => (Colors.green, 'Delivered'),
      OrderStatus.cancelled => (Colors.red, 'Cancelled'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderTrackingScreen(orderId: order['id'] as String, stationName: stationName, status: status),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(stationName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${order['jugs_ordered']} jugs of ${order['water_type']}'),
              Text('Total: ${formatPeso(totalAmount)}'),
              const SizedBox(height: 4),
              Text('Placed ${DateFormat('MMM d, yyyy h:mm a').format(createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              if (status == OrderStatus.assigned || status == OrderStatus.active) ...[
                const SizedBox(height: 8),
                const Row(children: [Icon(Icons.map_outlined, size: 16, color: Colors.blueGrey), SizedBox(width: 4), Text('Tap to track your driver', style: TextStyle(color: Colors.blueGrey, fontSize: 12))]),
              ],
              if (status == OrderStatus.done) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _showRatingDialog(order['station_id'] as String, stationName),
                    icon: const Icon(Icons.star_border, size: 18),
                    label: const Text('Rate this station'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRatingDialog(String stationId, String stationName) async {
    int rating = 5;
    final commentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Rate $stationName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarRatingInput(rating: rating, onChanged: (v) => setDialogState(() => rating = v)),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Optional comment', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _reviewService.submitReview(
                    stationId: stationId,
                    rating: rating,
                    comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
                  );
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit review: $e')));
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
