import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/portal/portal.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import '../../utils/log.dart';
import 'station_new_order_dialog.dart';
import '../../widgets/cancel_order_dialog.dart';
import '../../utils/phone_call.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../widgets/app_map_tiles.dart';
import '../../widgets/custom_map_marker.dart';
import '../../services/my_station.dart';

/// How one order's status reads on screen: its pill, its colour and the icon
/// on its card. Kept in one place so "assigned" doesn't mean amber on one
/// screen and blue on the next.
class _OrderLook {
  const _OrderLook(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  static _OrderLook of(String? status) {
    switch (status?.toLowerCase()) {
      case 'assigned':
        return const _OrderLook('ASSIGNED', AppColors.primary, Icons.assignment_ind_outlined);
      case 'active':
        return const _OrderLook('OUT FOR DELIVERY', AppColors.accent, Icons.local_shipping_outlined);
      case 'done':
        return const _OrderLook('DELIVERED', AppColors.cleared, Icons.check_circle_outline);
      case 'cancelled':
        return const _OrderLook('CANCELLED', AppColors.flagged, Icons.cancel_outlined);
      default:
        return const _OrderLook('NEW', AppColors.pendingClearance, Icons.fiber_new_outlined);
    }
  }
}

class MerchantOrdersScreen extends StatefulWidget {
  const MerchantOrdersScreen({super.key});

  @override
  State<MerchantOrdersScreen> createState() => _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends State<MerchantOrdersScreen> {
  final supabase = Supabase.instance.client;
  final _orderService = OrderService(SupabaseService.instance);
  bool _isLoading = true;

  List<dynamic> _newOrders = [];
  List<dynamic> _activeOrders = [];
  List<dynamic> _doneOrders = [];
  List<dynamic> _availableDrivers = [];
  String? _stationId;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;

  /// Customer name, phone and delivery coordinates per order
  /// (station_order_details). Owners can't read customers' profiles or the
  /// PostGIS delivery point directly, so app orders showed no name and the
  /// delivery point couldn't be shown at all.
  final Map<String, Map<String, dynamic>> _details = {};

  Future<void> _loadDetails(List<dynamic> orders) async {
    final missing = [for (final o in orders) if (!_details.containsKey(o['id'])) o['id'] as String];
    if (missing.isEmpty) return;
    try {
      final rows = await supabase.rpc('station_order_details', params: {'p_ids': missing});
      if (!mounted) return;
      setState(() {
        for (final r in rows as List) {
          _details[r['order_id'] as String] = Map<String, dynamic>.from(r as Map);
        }
      });
    } catch (e) {
      logError('station order details', e);
    }
  }

  void _showDeliveryPoint(dynamic order) {
    final d = _details[order['id']];
    final lat = (d?['latitude'] as num?)?.toDouble();
    final lng = (d?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This order has no delivery point (pickup at the station).')));
      return;
    }
    final point = LatLng(lat, lng);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Deliver to ${d?['customer_name'] ?? 'the customer'}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((order['delivery_address'] as String?)?.isNotEmpty ?? false) ...[
                Text(order['delivery_address'] as String),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FlutterMap(
                    options: MapOptions(initialCenter: point, initialZoom: 16),
                    children: [
                      const AppMapTiles(),
                      MarkerLayer(markers: [
                        Marker(point: point, width: 40, height: 40, child: const MapPin(kind: MapPinKind.deliveryAddress)),
                      ]),
                      const AppMapAttribution(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  void _setupRealtimeSubscription() async {
    try {
      // Owner or staff (services/my_station.dart).
      final stationData = await fetchMyStation(supabase);

      if (stationData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final stationId = stationData['id'];
      _stationId = stationId;

      await _refreshAvailableDrivers();

      // Refresh (app bar button / pull-to-refresh) previously called this
      // whole method again, stacking a brand new listener on top of every
      // prior one with none ever cancelled -- cancel any existing
      // subscription first so there's only ever one active at a time.
      await _ordersSubscription?.cancel();
      _ordersSubscription = supabase
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('station_id', stationId)
          .order('created_at', ascending: false)
          .listen((data) async {
            final pending = [];
            final active = [];
            final done = [];

            for (var order in data) {
              final status = order['status']?.toString().toLowerCase();
              if (status == 'pending') {
                pending.add(order);
              } else if (status == 'assigned' || status == 'active') {
                active.add(order);
              } else if (status == 'done') {
                done.add(order);
              }
              // 'cancelled' orders are intentionally excluded from every
              // tab -- they previously got miscounted into "Done".
            }

            unawaited(_loadDetails([...pending, ...active, ...done]));
            if (mounted) {
              setState(() {
                _newOrders = pending;
                _activeOrders = active;
                _doneOrders = done;
                _isLoading = false;
              });
            }
          });
    } catch (e) {
      logError('merchant orders', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  // Workers currently flagged are excluded from the assignment list -- a
  // flagged worker shouldn't be dispatched until WASA clears them. Re-run
  // right before showing the assign dialog (not just once on load) so a
  // driver flagged in the meantime doesn't still appear as assignable.
  Future<void> _refreshAvailableDrivers() async {
    if (_stationId == null) return;
    final driversResponse = await supabase
        .from('workers')
        .select('id, full_name, worker_code, vehicle_plate, phone_number, clearance_status')
        .eq('station_id', _stationId!)
        // Only cleared drivers deliver: a new driver waits for WASA to
        // check their documents, and an open incident puts a driver back to
        // pending (set_order_status refuses both).
        .eq('clearance_status', 'cleared');
    _availableDrivers = driversResponse;
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }
    await callPhone(context, phoneNumber);
  }

  Future<void> _rejectOrder(String orderId) async {
    final reason = await showCancelOrderDialog(
      context,
      byCustomer: false,
      summary: 'Order #${orderId.substring(0, 6).toUpperCase()}',
    );
    if (reason == null) return;

    try {
      await _orderService.ownerCancelOrder(orderId, reason: reason);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error rejecting order. ${describeError(e)}')));
      }
    }
  }

  Future<void> _unassignOrder(String orderId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Unassign Driver?',
      message: 'This order goes back to the New/Pending queue so it can be reassigned to another driver.',
      confirmLabel: 'Unassign',
    );
    if (!confirmed) return;

    try {
      await _orderService.unassignOrder(orderId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error unassigning order. ${describeError(e)}')));
      }
    }
  }

  Future<void> _assignDriver(String orderId, String workerId) async {
    try {
      await _orderService.assignDriver(orderId, workerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver successfully assigned to order!'), backgroundColor: AppColors.cleared),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error assigning driver. ${describeError(e)}')));
      }
    }
  }

  Future<void> _showAssignDriverDialog(String orderId) async {
    try {
      await _refreshAvailableDrivers();
    } catch (e) {
      logError('merchant available drivers', e);
    }
    if (!mounted) return;

    if (_availableDrivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No cleared drivers. A new driver can deliver once WASA approves their documents; '
              'share your invite code from the Worker Registry to add one.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Driver to Order'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _availableDrivers.length,
            itemBuilder: (context, index) {
              final driver = _availableDrivers[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(driver['full_name'] ?? 'Unnamed Driver'),
                // The worker code tells apart two drivers with the same name.
                subtitle: Text('${driver['worker_code'] ?? ''} · Plate: ${driver['vehicle_plate'] ?? 'N/A'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.phone, color: AppColors.cleared),
                  tooltip: 'Call this driver',
                  onPressed: () => _makePhoneCall(driver['phone_number'] ?? ''),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _assignDriver(orderId, driver['id']);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Column(
          children: [
            PortalPageHeader(
              eyebrow: 'Your station',
              title: 'Live Order Pipeline',
              subtitle: 'New orders appear the moment a customer places one',
              actions: [
                // Phone and walk-in customers (station_create_order).
                if (_stationId != null)
                  FilledButton.icon(
                    onPressed: () => showStationNewOrderDialog(context, stationId: _stationId!),
                    icon: const Icon(Icons.add),
                    label: const Text('New order'),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh orders',
                  onPressed: () => _setupRealtimeSubscription(),
                ),
              ],
              // A TabBar has a fixed height, so past about 130% system text
              // the labels clip inside it. Everything else on the page scales
              // freely -- this is the same clamp the bottom nav uses.
              bottom: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: TabBar(
                  // Tabs scroll sideways on a phone; fixed, the last ones were cut
                  // off ("Crede...", "Settlements (3 waitin...").
                  isScrollable: MediaQuery.sizeOf(context).width < 600,
                  tabAlignment: MediaQuery.sizeOf(context).width < 600 ? TabAlignment.start : null,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  tabs: const [
                    Tab(text: 'New'),
                    Tab(text: 'Active'),
                    Tab(text: 'Done'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _buildOrderList(_newOrders, 'pending'),
                        _buildOrderList(_activeOrders, 'active'),
                        _buildOrderList(_doneOrders, 'done'),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(List<dynamic> orders, String listType) {
    final density = PortalDensity.of(context);

    if (orders.isEmpty) {
      // Inside a ListView rather than a bare Center so pull-to-refresh still
      // works on an empty tab -- previously the one state where you most
      // wanted to refresh was the one you couldn't pull.
      return RefreshIndicator(
        onRefresh: () async => _setupRealtimeSubscription(),
        child: ListView(
          padding: density.pagePadding,
          children: [
            const SizedBox(height: 24),
            _emptyStateFor(listType),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _setupRealtimeSubscription(),
      child: ListView.builder(
        padding: density.pagePadding,
        itemCount: orders.length,
        itemBuilder: (context, index) => _buildOrderCard(orders[index], listType, density),
      ),
    );
  }

  Widget _emptyStateFor(String listType) {
    switch (listType) {
      case 'active':
        return const PortalEmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'Nothing out for delivery',
          message: 'Orders you have assigned to a driver stay here until they are delivered.',
        );
      case 'done':
        return const PortalEmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No completed orders yet',
          message: 'Delivered orders are kept here so you can look back over them.',
        );
      default:
        return const PortalEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No new orders',
          message: 'When a customer places an order it appears here straight away -- you do not need to refresh.',
        );
    }
  }

  Widget _buildOrderCard(dynamic order, String listType, PortalDensity density) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = order['status']?.toString();
    final look = _OrderLook.of(status);
    final shortId = order['id'].toString().substring(0, 6).toUpperCase();
    final time = DateFormat('h:mm a').format(DateTime.parse(order['created_at']));

    return PortalCard(
      lift: false,
      accent: look.color,
      margin: EdgeInsets.only(bottom: density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: StatusTint.surface(context, look.color), shape: BoxShape.circle),
                child: Icon(look.icon, color: StatusTint.onTint(context, look.color), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$shortId', style: theme.textTheme.titleMedium),
                    Text(
                      switch (order['order_channel']) {
                        'phone' => 'Phone order · ${order['guest_name'] ?? ''} · $time',
                        'walk_in' => 'Walk-in · ${order['guest_name'] ?? ''} · $time',
                        // App orders: the customer's name, from
                        // station_order_details once it has loaded.
                        _ => '${_details[order['id']]?['customer_name'] ?? 'App order'} · $time',
                      },
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (density.isWide) ...[
                const SizedBox(width: 8),
                StatusPill(label: look.label, color: look.color, icon: look.icon),
              ],
            ],
          ),
          // On a phone the pill takes its own line. Beside the order number
          // it is a non-flexible child of a Row, so it is laid out with
          // unbounded width and a label like "OUT FOR DELIVERY" at large
          // system text never wraps -- it just runs off the card. As a child
          // of this Column its width is bounded, so it wraps instead.
          if (!density.isWide) ...[
            const SizedBox(height: 10),
            StatusPill(label: look.label, color: look.color, icon: look.icon),
          ],
          const SizedBox(height: 12),
          PortalLineAmount(
            line: Text(
              describeOrderLine(
                quantity: (order['jugs_ordered'] as num).toInt(),
                waterType: order['water_type'] as String? ?? '',
                containerCode: order['jug_type'] as String?,
                productKind: order['product_kind'] as String?,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            // The amount is what an owner scans for, so it gets the display
            // face rather than being run together with the order line.
            amount: Text(
              formatPeso((order['total_amount'] as num?)?.toDouble() ?? 0),
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // The written delivery address, so whoever dispatches knows the
          // street and landmark, not just the pin.
          if ((order['delivery_address'] as String?)?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(order['delivery_address'] as String, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
          if (listType == 'active') ...[
            const SizedBox(height: 4),
            // Wrap rather than Row: at large system text two buttons side by
            // side no longer fit a phone's width.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                // set_order_status only allows an owner to unassign
                // (assigned -> pending); once a driver has actually started
                // the delivery (active), this would always fail server-side,
                // so it isn't offered as a button then.
                if (status?.toLowerCase() == 'assigned')
                  TextButton.icon(
                    onPressed: () => _unassignOrder(order['id']),
                    icon: const Icon(Icons.person_remove_outlined, size: 16),
                    label: const Text('Unassign'),
                  ),
                // Cancelling is allowed until the driver sets out
                // (cancel_order); out for delivery, it isn't offered.
                if (status?.toLowerCase() == 'assigned')
                  TextButton.icon(
                    onPressed: () => _rejectOrder(order['id']),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel order'),
                  ),
                TextButton.icon(
                  onPressed: () {
                    final String customerPhone = order['customer_phone'] ?? order['guest_phone'] ??
                        _details[order['id']]?['customer_phone'] ?? '';
                    _makePhoneCall(customerPhone);
                  },
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call customer'),
                ),
                TextButton.icon(
                  onPressed: () => _showDeliveryPoint(order),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Delivery point'),
                ),
              ],
            ),
          ],
          // A driver reported this delivery as failed and it came back to the
          // queue (driver_report_failed_delivery). Say so, and why, so the
          // owner reassigns or calls the customer rather than wondering.
          if (listType == 'pending' && order['failure_reason'] != null) ...[
            const SizedBox(height: 12),
            StatusCallout(
              accent: AppColors.pendingClearance,
              icon: Icons.report_gmailerrorred_outlined,
              title: 'Last delivery attempt failed: ${order['failure_reason']}',
              message: '${order['failed_at'] != null ? 'Reported ${DateFormat('MMM d, h:mm a').format(DateTime.parse(order['failed_at'] as String).toLocal())}. ' : ''}'
                  'Reassign a driver, call the customer, or reject the order.',
            ),
          ],
          if (listType == 'pending') ...[
            const SizedBox(height: 14),
            PortalActionRow(
              children: [
                OutlinedButton(
                  onPressed: () => _rejectOrder(order['id']),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => _showAssignDriverDialog(order['id']),
                  child: const Text('Assign & accept'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
