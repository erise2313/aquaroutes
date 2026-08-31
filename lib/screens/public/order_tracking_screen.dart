import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/order.dart';
import '../../services/driver_tracking_service.dart';
import '../../services/supabase_service.dart';

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

  bool get _isTrackable => widget.status == OrderStatus.assigned || widget.status == OrderStatus.active;

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
          _error = 'Could not load driver info: $e';
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_empty, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      widget.status == OrderStatus.pending
                          ? 'Waiting for a driver to be assigned.'
                          : widget.status == OrderStatus.done
                          ? 'This order has been delivered.'
                          : 'This order was cancelled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            )
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : Column(
              children: [
                Expanded(
                  child: _driver != null && _driver!.hasPosition
                      ? FlutterMap(
                          options: MapOptions(initialCenter: LatLng(_driver!.lat!, _driver!.lng!), initialZoom: 15),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ph.gentriwasa.aquaroute',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(_driver!.lat!, _driver!.lng!),
                                width: 44,
                                height: 44,
                                child: const Icon(Icons.local_shipping, color: AppColors.primary, size: 36),
                              ),
                            ]),
                          ],
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _driver == null ? 'Driver assigned -- waiting for their first location update.' : 'Waiting for driver location…',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                ),
                if (_driver?.driverName != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))]),
                    child: Row(
                      children: [
                        const CircleAvatar(backgroundColor: AppColors.primary, child: Icon(Icons.person, color: Colors.white)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_driver!.driverName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Your driver', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
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
              ],
            ),
    );
  }
}
