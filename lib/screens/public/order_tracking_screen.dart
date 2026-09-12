import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/order.dart';
import '../../models/order_status_look.dart';
import '../../services/driver_tracking_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_map_tiles.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../utils/error_text.dart';

/// Per-order detail screen with a live driver map, shared by logged-in
/// customers (my_orders_screen.dart, guestPhone omitted) and guests
/// (track_order_screen.dart, guestPhone required) -- both authorize
/// identically via get_active_delivery_driver()'s own checks, not RLS
/// (see supabase/patch_tier1_tier2_features.sql).
///
/// Polls rather than subscribing to a Realtime channel: driver_states
/// already updates on a 10m distance filter (location_service.dart), so an
/// 8s poll is simple and works the same way for guest and authenticated
/// callers instead of branching auth logic per flow.
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.stationName,
    required this.status,
    this.guestPhone,
  });

  final String orderId;
  final String stationName;
  final OrderStatus status;
  final String? guestPhone;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final _driverTrackingService = DriverTrackingService(SupabaseService.instance);

  Timer? _pollTimer;
  ActiveDeliveryDriver? _driver;
  bool _isLoading = true;
  String? _error;

  bool get _isTrackable => OrderStatusLook.isTrackable(widget.status);

  @override
  void initState() {
    super.initState();
    if (_isTrackable) {
      _fetchDriver();
      _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _fetchDriver());
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDriver() async {
    try {
      final driver = await _driverTrackingService.fetchActiveDriver(orderId: widget.orderId, guestPhone: widget.guestPhone);
      if (mounted) {
        setState(() {
          _driver = driver;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load driver info. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _callDriver(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone dialer.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.stationName)),
      body: !_isTrackable
          ? _buildUntrackableState()
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          // Was bare text with no way out -- the only error state in the
          // customer screens that couldn't be retried.
          : _error != null
          ? ErrorState(message: _error!, onRetry: _fetchDriver)
          : Column(
              children: [
                Expanded(
                  child: _driver != null && _driver!.hasPosition
                      ? FlutterMap(
                          options: MapOptions(initialCenter: LatLng(_driver!.lat!, _driver!.lng!), initialZoom: 15),
                          children: [
                            const AppMapTiles(),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(_driver!.lat!, _driver!.lng!),
                                width: 44,
                                height: 44,
                                child: const Icon(Icons.local_shipping, color: AppColors.primary, size: 36),
                              ),
                            ]),
                            const AppMapAttribution(),
                          ],
                        )
                      : PortalEmptyState(
                          icon: Icons.my_location_outlined,
                          title: 'Waiting for a location',
                          message: _driver == null
                              ? 'A driver has been assigned. Their position appears here as soon as they send their first update.'
                              : 'Your driver is on the way -- waiting for their next location update.',
                        ),
                ),
                if (_driver?.driverName != null) _buildDriverCard(),
              ],
            ),
    );
  }

  Widget _buildUntrackableState() {
    final (title, message) = switch (widget.status) {
      OrderStatus.pending => ('Waiting for a driver', 'The station has your order. This map opens once they assign a driver to it.'),
      OrderStatus.done => ('Delivered', 'This order has been delivered. Thanks for ordering.'),
      _ => ('Cancelled', 'This order was cancelled, so there is nothing to track.'),
    };

    return PortalEmptyState(icon: Icons.hourglass_empty, title: title, message: message);
  }

  Widget _buildDriverCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // top: false so the map still runs full-bleed behind the status bar, but
    // the card itself clears the navigation bar -- under edge-to-edge this is
    // the bottom-most element, and the call button would otherwise sit under
    // the gesture area.
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: AppColors.primary, child: Icon(Icons.person, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_driver!.driverName!, style: theme.textTheme.titleMedium),
                  Text('Your driver', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (_driver!.driverPhone != null && _driver!.driverPhone!.isNotEmpty)
              IconButton.filled(
                onPressed: () => _callDriver(_driver!.driverPhone!),
                icon: const Icon(Icons.phone),
                tooltip: 'Call driver',
              ),
          ],
        ),
      ),
    );
  }
}
