import 'package:flutter/material.dart';
import '../../constants/brand_tokens.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/order.dart';
import '../../models/order_status_look.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';

/// The customer's name, as given on the order.
String adminOrderCustomerName(Map<String, dynamic> row) => (row['customer_name'] as String?) ?? 'Customer';

/// The delivery's contact number, under the same rule.
String? adminOrderCustomerPhone(Map<String, dynamic> row) => row['customer_phone'] as String?;

/// The short order number customers and stations see ("#A1B2C3").
String adminOrderNumber(Map<String, dynamic> row) => '#${(row['id'] as String).substring(0, 6).toUpperCase()}';

String _orderLine(Map<String, dynamic> row) => describeOrderLine(
      quantity: (row['jugs_ordered'] as num?)?.toInt() ?? 0,
      waterType: row['water_type'] as String? ?? '',
      containerCode: row['jug_type'] as String?,
      productKind: row['product_kind'] as String?,
    );

/// Opens a reported order in full. Officers don't have a list of stations'
/// orders (decision of 18 Oct 2026); they reach an order only through a
/// customer's report about it, and admin_list_orders returns only those.
Future<void> showReportedOrder(BuildContext context, String orderId) async {
  Map<String, dynamic>? order;
  try {
    final rows = await Supabase.instance.client.rpc('admin_list_orders', params: {'p_limit': 2000});
    order = List<Map<String, dynamic>>.from(rows as List).where((o) => o['id'] == orderId).firstOrNull;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the order. ${describeError(e)}')));
    }
    return;
  }
  if (!context.mounted) return;
  if (order == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That order is no longer available.')));
    return;
  }
  await showDialog<bool>(context: context, builder: (_) => _AdminOrderDialog(order: order!));
}

/// One order in full, with the cancellation an officer may make.
class _AdminOrderDialog extends StatefulWidget {
  const _AdminOrderDialog({required this.order});

  final Map<String, dynamic> order;

  @override
  State<_AdminOrderDialog> createState() => _AdminOrderDialogState();
}

class _AdminOrderDialogState extends State<_AdminOrderDialog> {
  final _orderService = OrderService(SupabaseService.instance);
  bool _busy = false;

  Future<void> _cancel() async {
    final o = widget.order;
    final ok = await showConfirmDialog(
      context,
      title: 'Cancel order ${adminOrderNumber(o)}?',
      message: 'The customer and the station are notified that it was cancelled. This cannot be undone.',
      confirmLabel: 'Cancel order',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _orderService.ownerCancelOrder(o['id'] as String);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel the order. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final theme = Theme.of(context);
    final status = orderStatusFromString(o['status'] as String? ?? 'pending');
    final look = OrderStatusLook.of(status);
    final fmt = DateFormat('MMM d, yyyy · h:mm a');
    String? when(String key) => o[key] == null ? null : fmt.format(DateTime.parse(o[key] as String).toLocal());

    final rows = <(String, String?)>[
      ('Station', o['station_name'] as String?),
      ('Customer', adminOrderCustomerName(o)),
      ('Contact number', adminOrderCustomerPhone(o)),
      ('Items', _orderLine(o)),
      ('Total', formatPeso((o['total_amount'] as num?) ?? 0)),
      ('Payment', [
        (o['payment_method'] as String? ?? '').toUpperCase(),
        if (o['payment_collected'] == true) 'collected',
      ].where((s) => s.isNotEmpty).join(' · ')),
      ('Placed', when('created_at')),
      ('Scheduled for', when('scheduled_for')),
      ('Driver', o['driver_name'] as String?),
      ('Delivery failed', o['failure_reason'] == null ? null : '${o['failure_reason']} (${when('failed_at')})'),
    ];

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Order ${adminOrderNumber(o)}')),
          AdminStatusPill(label: look.label, color: look.color, icon: look.icon),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value) in rows)
                if (value != null && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodySmall)),
                        Expanded(child: SelectableText(value)),
                      ],
                    ),
                  ),
              const SizedBox(height: 4),
              SelectableText('Order ID: ${o['id']}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        if (OrderStatusLook.isCancellable(status))
          TextButton(
            onPressed: _busy ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: BrandStatus.dangerFor(Theme.of(context).brightness)),
            child: const Text('Cancel order'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Close')),
      ],
    );
  }
}
