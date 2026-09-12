import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_colors.dart';

import '../../models/order.dart';
import '../../models/order_status_look.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/portal/portal.dart';
import 'order_tracking_screen.dart';
import '../app_route.dart';
import '../../utils/error_text.dart';

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
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = result == null ? 'No matching order found. Check the order ID and phone number.' : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not look up this order. ${describeError(e)}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Was a hard-coded blue bar with white text, which ignored the theme in
      // both modes.
      appBar: AppBar(title: const Text('Track my order')),
      body: SingleChildScrollView(
        padding: PortalDensity.of(context).pagePadding,
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
              PortalActionRow(
                children: [
                  FilledButton(
                    onPressed: _isLoading ? null : _lookup,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Track order'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                // Was bare red text; a callout tints from the theme and says
                // what to do about it.
                StatusCallout(
                  accent: AppColors.flagged,
                  icon: Icons.error_outline,
                  title: "We couldn't find that order",
                  message: _error!,
                ),
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

  Future<void> _cancelOrder(GuestOrderStatus result) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel Order?',
      message: 'Your ${formatPeso(result.totalAmount)} order from ${result.stationName} will be cancelled. This cannot be undone.',
      confirmLabel: 'Cancel Order',
    );
    if (!confirmed) return;

    try {
      await _orderService.cancelOrder(orderId: result.id, guestPhone: _phoneController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order cancelled.')));
      }
      _lookup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel order. ${describeError(e)}')));
      }
    }
  }

  Widget _buildResultCard(GuestOrderStatus result) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The same mapping my_orders_screen uses -- this screen used to carry its
    // own copy, and the two had drifted in wording.
    final look = OrderStatusLook.of(result.status);

    return PortalCard(
      lift: false,
      accent: look.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.stationName, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          StatusPill(label: look.label, color: look.color),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text(result.lineDescription, style: theme.textTheme.bodyMedium)),
              const SizedBox(width: 12),
              Text(
                formatPeso(result.totalAmount),
                style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Placed ${DateFormat('MMM d, yyyy h:mm a').format(result.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (OrderStatusLook.isTrackable(result.status)) ...[
            const SizedBox(height: 12),
            PortalActionRow(
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    appRoute(OrderTrackingScreen(
                      orderId: result.id,
                      stationName: result.stationName,
                      status: result.status,
                      guestPhone: _phoneController.text.trim(),
                    )),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Track my driver'),
                ),
              ],
            ),
          ],
          if (OrderStatusLook.isCancellable(result.status)) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _cancelOrder(result),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel order'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
