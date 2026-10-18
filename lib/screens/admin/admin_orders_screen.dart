import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_palette.dart';
import '../../constants/app_colors.dart';
import '../../models/order.dart';
import '../../models/order_status_look.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/csv_download.dart';
import '../../utils/csv_export.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';

/// How many of the most recent orders the screen loads. Enough for any
/// complaint an officer will be asked about; the export carries the same set.
const adminOrdersLimit = 500;

/// The columns the Orders screen reads. Two foreign keys point at
/// water_stations (the delivering station and a jug exchange's origin), so
/// the station embed names its key.
const adminOrdersSelect = 'id, status, created_at, scheduled_for, jugs_ordered, water_type, jug_type, product_kind, '
    'total_amount, payment_method, payment_collected, customer_phone, guest_name, guest_phone, '
    'failure_reason, failed_at, '
    'water_stations!orders_station_id_fkey(station_name), '
    'profiles!orders_customer_profile_id_fkey(full_name, phone_number), '
    'workers!orders_driver_worker_id_fkey(full_name)';

/// Narrows loaded orders by free text (customer name or phone, station,
/// order number) plus an optional status and age. Top-level and pure so the
/// matching rules are unit-testable, like filterMemberships.
List<Map<String, dynamic>> filterAdminOrders(
  List<Map<String, dynamic>> rows, {
  String query = '',
  String? status,
  int? withinDays,
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  final cutoff = withinDays == null ? null : (now ?? DateTime.now()).subtract(Duration(days: withinDays));
  return rows.where((row) {
    if (status != null && row['status'] != status) return false;
    if (cutoff != null) {
      final created = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (created == null || created.isBefore(cutoff)) return false;
    }
    if (q.isEmpty) return true;
    final fields = [
      adminOrderCustomerName(row),
      adminOrderCustomerPhone(row),
      row['water_stations']?['station_name'] as String?,
      row['id'] as String?,
    ];
    return fields.any((f) => f != null && f.toLowerCase().contains(q));
  }).toList();
}

/// The customer's name: their account name, or the name given on an old
/// guest order.
String adminOrderCustomerName(Map<String, dynamic> row) =>
    (row['profiles']?['full_name'] as String?) ?? (row['guest_name'] as String?) ?? 'Customer';

/// The contact number given for the delivery, falling back to the account's.
String? adminOrderCustomerPhone(Map<String, dynamic> row) =>
    (row['customer_phone'] as String?) ?? (row['guest_phone'] as String?) ?? (row['profiles']?['phone_number'] as String?);

/// The short order number customers and stations see ("#A1B2C3").
String adminOrderNumber(Map<String, dynamic> row) => '#${(row['id'] as String).substring(0, 6).toUpperCase()}';

String _orderLine(Map<String, dynamic> row) => describeOrderLine(
      quantity: (row['jugs_ordered'] as num?)?.toInt() ?? 0,
      waterType: row['water_type'] as String? ?? '',
      containerCode: row['jug_type'] as String?,
      productKind: row['product_kind'] as String?,
    );

/// Every order in the association, for officers.
///
/// Officers could read orders in the database all along but had no screen
/// for them, so a customer's complaint about a station could not be looked
/// into from the portal. This lists the most recent orders with their
/// customer, station, driver and status; an officer can open one and, while
/// it has not gone out for delivery, cancel it (set_order_status allows a
/// WASA officer the same cancellation a station owner has).
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  String _query = '';
  String? _status;
  String? _period;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('orders')
          .select(adminOrdersSelect)
          .order('created_at', ascending: false)
          .limit(adminOrdersLimit);
      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load orders. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible => filterAdminOrders(
        _orders,
        query: _query,
        status: _status,
        withinDays: _period == null ? null : int.parse(_period!),
      );

  void _exportCsv() {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final csv = buildCsv(
      const ['Order', 'Placed', 'Station', 'Customer', 'Phone', 'Items', 'Total', 'Status', 'Driver', 'Failed delivery'],
      _visible
          .map((o) => [
                adminOrderNumber(o),
                fmt.format(DateTime.parse(o['created_at'] as String).toLocal()),
                (o['water_stations']?['station_name'] as String?) ?? '',
                adminOrderCustomerName(o),
                adminOrderCustomerPhone(o) ?? '',
                _orderLine(o),
                ((o['total_amount'] as num?) ?? 0).toStringAsFixed(2),
                o['status'] as String? ?? '',
                (o['workers']?['full_name'] as String?) ?? '',
                (o['failure_reason'] as String?) ?? '',
              ])
          .toList(),
    );
    if (!downloadCsv(csvFileName('orders'), csv)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exporting works in the web admin portal.')));
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _AdminOrderDialog(order: order));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final isFiltered = _query.trim().isNotEmpty || _status != null || _period != null;

    return Column(
      children: [
        AdminPageHeader(
          eyebrow: 'Network',
          title: 'Orders',
          subtitle: _orders.isEmpty
              ? 'Every order placed with a member station'
              : _orders.length >= adminOrdersLimit
                  ? 'The $adminOrdersLimit most recent orders'
                  : '${_orders.length} orders',
          actions: [
            if (_orders.isNotEmpty)
              TextButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.download_outlined), label: const Text('Export')),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 6))
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : _orders.isEmpty
                      ? const PortalEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No orders yet',
                          message: 'Orders customers place with member stations appear here.',
                        )
                      : Column(
                          children: [
                            AdminFilterBar(
                              searchHint: 'Search by customer, phone, station or order number',
                              searchController: _searchController,
                              onSearchChanged: (v) => setState(() => _query = v),
                              resultSummary: isFiltered ? '${visible.length} of ${_orders.length} orders' : null,
                              filters: [
                                AdminFilterGroup(
                                  label: 'Status',
                                  options: const {
                                    null: 'Any',
                                    'pending': 'Pending',
                                    'assigned': 'Driver assigned',
                                    'active': 'Out for delivery',
                                    'done': 'Delivered',
                                    'cancelled': 'Cancelled',
                                  },
                                  selected: _status,
                                  onChanged: (v) => setState(() => _status = v),
                                ),
                                AdminFilterGroup(
                                  label: 'Placed',
                                  options: const {null: 'Any time', '1': 'Today', '7': 'Last 7 days', '30': 'Last 30 days'},
                                  selected: _period,
                                  onChanged: (v) => setState(() => _period = v),
                                ),
                              ],
                            ),
                            Expanded(
                              child: visible.isEmpty
                                  ? PortalEmptyState(
                                      icon: Icons.search_off,
                                      title: 'No orders match',
                                      message: 'Nothing matches the current search and filters.',
                                      action: TextButton.icon(
                                        onPressed: () => setState(() {
                                          _searchController.clear();
                                          _query = '';
                                          _status = null;
                                          _period = null;
                                        }),
                                        icon: const Icon(Icons.clear),
                                        label: const Text('Clear filters'),
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _load,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                        itemCount: visible.length,
                                        itemBuilder: (context, i) => _buildTile(visible[i]),
                                      ),
                                    ),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> order) {
    final palette = AdminPalette.of(context);
    final look = OrderStatusLook.of(orderStatusFromString(order['status'] as String? ?? 'pending'));
    final failed = order['failed_at'] != null && order['status'] == 'pending';
    final placed = DateFormat('MMM d, h:mm a').format(DateTime.parse(order['created_at'] as String).toLocal());

    return PortalCard(
      margin: const EdgeInsets.only(bottom: 10),
      accent: failed ? AppColors.flagged : look.color,
      onTap: () => _open(order),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${adminOrderNumber(order)} · ${(order['water_stations']?['station_name'] as String?) ?? 'Unknown station'}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink),
                ),
                const SizedBox(height: 2),
                Text('${_orderLine(order)} · ${formatPeso((order['total_amount'] as num?) ?? 0)}', style: TextStyle(color: palette.inkMuted)),
                Text('${adminOrderCustomerName(order)} · $placed', style: TextStyle(color: palette.inkMuted)),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Delivery failed: ${order['failure_reason']}', style: const TextStyle(color: AppColors.flagged)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AdminStatusPill(label: look.label, color: look.color),
        ],
      ),
    );
  }
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
      ('Station', o['water_stations']?['station_name'] as String?),
      ('Customer', adminOrderCustomerName(o) + (o['profiles'] == null && o['guest_name'] != null ? ' (guest order)' : '')),
      ('Contact number', adminOrderCustomerPhone(o)),
      ('Items', _orderLine(o)),
      ('Total', formatPeso((o['total_amount'] as num?) ?? 0)),
      ('Payment', [
        (o['payment_method'] as String? ?? '').toUpperCase(),
        if (o['payment_collected'] == true) 'collected',
      ].where((s) => s.isNotEmpty).join(' · ')),
      ('Placed', when('created_at')),
      ('Scheduled for', when('scheduled_for')),
      ('Driver', o['workers']?['full_name'] as String?),
      ('Delivery failed', o['failure_reason'] == null ? null : '${o['failure_reason']} (${when('failed_at')})'),
    ];

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Order ${adminOrderNumber(o)}')),
          AdminStatusPill(label: look.label, color: look.color),
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
            style: TextButton.styleFrom(foregroundColor: AppColors.flagged),
            child: const Text('Cancel order'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Close')),
      ],
    );
  }
}
