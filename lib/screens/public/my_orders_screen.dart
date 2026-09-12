import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/order.dart';
import '../../models/order_status_look.dart';
import '../../services/order_service.dart';
import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/star_rating.dart';
import 'order_tracking_screen.dart';
import 'quick_order_screen.dart';
import '../app_route.dart';
import '../../utils/error_text.dart';

/// Authenticated customer's persistent order history -- the real fix for
/// "order tracking is device-local only": orders.customer_profile_id +
/// orders_customer_read RLS (0009_rls.sql) already scope this correctly,
/// this screen just reads it. Unlike TrackOrderScreen (phone-verified guest
/// lookup, one order at a time), this is a full list, always available
/// across devices since it's tied to the account, not local storage.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.showAppBar = true});

  /// False when this is the Orders tab rather than a pushed screen.
  ///
  /// PublicHomeScreen's shell already supplies an app bar, so rendering one
  /// here too stacked two of them in the tab -- the same double-chrome fault
  /// the admin portal had.
  final bool showAppBar;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final _supabase = Supabase.instance.client;
  final _reviewService = ReviewService(SupabaseService.instance);
  final _orderService = OrderService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser!.id;
      final rows = await _supabase
          .from('orders')
          // The join is named explicitly: orders has two foreign keys to
          // water_stations -- station_id and jug_exchange_origin_station_id,
          // the second added with jug exchange -- so a bare
          // `water_stations(...)` became ambiguous and PostgREST refused it
          // outright ("more than one relationship was found"), breaking this
          // screen entirely. The constraint name survives a column rename.
          .select('id, station_id, status, jugs_ordered, water_type, jug_type, product_kind, product_id, unit_price, total_amount, created_at, water_stations!orders_station_id_fkey(station_name)')
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
          _error = 'Could not load your orders. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('My Orders')) : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _orders.isEmpty
          // Inside a scrollable so pull-to-refresh still works on an empty
          // list -- the one state where you most want to refresh.
          ? RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: density.pagePadding,
                children: const [
                  SizedBox(height: 24),
                  PortalEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No orders yet',
                    message: 'Once you place an order it appears here, and you can follow its driver on a map.',
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: density.pagePadding,
                itemCount: _orders.length,
                itemBuilder: (context, index) =>
                    _buildOrderCard(_orders[index], last: index == _orders.length - 1, density: density),
              ),
            ),
    );
  }

  Future<void> _cancelOrder(String orderId, String stationName, double totalAmount) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel Order?',
      message: 'Your ${formatPeso(totalAmount)} order from $stationName will be cancelled. This cannot be undone.',
      confirmLabel: 'Cancel Order',
    );
    if (!confirmed) return;

    try {
      await _orderService.cancelOrder(orderId: orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel order. ${describeError(e)}')));
      }
    }
  }

  String _orderLineText(Map<String, dynamic> order) {
    return describeOrderLine(
      quantity: (order['jugs_ordered'] as num).toInt(),
      waterType: order['water_type'] as String? ?? '',
      containerCode: order['jug_type'] as String?,
      productKind: order['product_kind'] as String?,
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = orderStatusFromString(order['status'] as String? ?? 'pending');
    final stationName = (order['water_stations']?['station_name'] as String?) ?? 'Unknown Station';
    final createdAt = DateTime.parse(order['created_at'] as String);
    final totalAmount = (order['total_amount'] as num).toDouble();
    final look = OrderStatusLook.of(status);

    return PortalCard(
      accent: look.color,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      onTap: () => Navigator.push(
        context,
        appRoute(OrderTrackingScreen(orderId: order['id'] as String, stationName: stationName, status: status)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stationName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          // On its own line rather than beside the station name: a pill is a
          // non-flexible child of a Row and is laid out with unbounded width,
          // so a long label like OUT FOR DELIVERY could never wrap there.
          StatusPill(label: look.label, color: look.color),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(_orderLineText(order), style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              Text(
                formatPeso(totalAmount),
                style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Placed ${DateFormat('MMM d, yyyy h:mm a').format(createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (OrderStatusLook.isTrackable(status)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.map_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Tap to track your driver',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
          if (OrderStatusLook.isCancellable(status)) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _cancelOrder(order['id'] as String, stationName, totalAmount),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel order'),
              ),
            ),
          ],
          if (status == OrderStatus.done || status == OrderStatus.cancelled) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Water is a weekly repeat purchase; this reopens the order
                // form on the same station, product and quantity.
                if (order['product_id'] != null)
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      appRoute(QuickOrderScreen(
                        prefill: OrderPrefill(
                          stationId: order['station_id'] as String,
                          productId: order['product_id'] as String,
                          quantity: (order['jugs_ordered'] as num).toInt(),
                          unitPrice: (order['unit_price'] as num?)?.toDouble(),
                        ),
                      )),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Order again'),
                  ),
                if (status == OrderStatus.done)
                  OutlinedButton.icon(
                    onPressed: () => _showRatingDialog(order['station_id'] as String, stationName),
                    icon: const Icon(Icons.star_border, size: 18),
                    label: const Text('Rate this station'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showRatingDialog(String stationId, String stationName) async {
    int rating = 0;
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
              onPressed: rating == 0
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      try {
                        await _reviewService.submitReview(
                          stationId: stationId,
                          rating: rating,
                          comment: commentController.text.trim().isEmpty ? null : commentController.text.trim(),
                        );
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit review. ${describeError(e)}')));
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
