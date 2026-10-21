import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_palette.dart';
import '../../models/order.dart';
import '../../models/permit.dart';
import '../../services/jug_ledger_service.dart';
import '../../services/location_service.dart';
import '../../services/order_service.dart';
import '../../services/route_optimization.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../utils/delivery_distance.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_map_tiles.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../public/bulletin_board_screen.dart';
import 'driver_profile_screen.dart';
import '../../utils/error_text.dart';
import '../../utils/log.dart';
import '../../widgets/delivery_panel_layout.dart';
import '../../utils/phone_call.dart';
import 'package:aquaroute/constants/brand_tokens.dart';


class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  late DriverPalette driverPalette;
  final supabase = Supabase.instance.client;
  final LocationService _locationService = LocationService();
  final RouteOptimizationService _routeService = RouteOptimizationService();
  final _orderService = OrderService(SupabaseService.instance);
  final _credentialService = WorkerCredentialService(SupabaseService.instance);
  final _jugService = JugLedgerService(SupabaseService.instance);

  bool _isLoading = true;
  bool _isOnDuty = false;
  String? _workerId;
  String? _stationId;
  LatLng? _stationLocation;
  int _missingCredentialsCount = 0;

  Map<String, dynamic>? _currentActiveOrder;

  String _customerName = "Loading...";
  String _customerPhone = "";
  String _stationPhone = "";
  String _stationName = "Water Station";
  double _totalAmount = 0.0;
  LatLng? _destination;

  List<Map<String, dynamic>> _orderedStops = [];

  /// The line drawn on the map: road geometry from the route-optimize Edge
  /// Function, or a straight-line estimate that [_routeApproximate] flags.
  List<LatLng> _routePoints = [];
  bool _routeApproximate = false;
  String? _routeSummary;

  @override
  void initState() {
    super.initState();
    _initializeDriver();
  }

  @override
  void dispose() {
    // Best-effort cleanup: if this screen is torn down while on-duty
    // (e.g. AuthGate swaps the driver out on sign-out/session change,
    // rather than them tapping the OFF-DUTY switch first), the GPS
    // position-stream subscription would otherwise keep running and
    // upserting driver_states indefinitely -- a location-privacy and
    // battery leak. Not awaited since dispose() can't be async.
    if (_isOnDuty && _workerId != null) {
      _locationService.stopTracking(_workerId!);
    }
    super.dispose();
  }

  Future<void> _initializeDriver() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      final worker = await supabase.from('workers').select('id, station_id').eq('profile_id', userId).maybeSingle();

      if (worker == null) {
        throw Exception("You are not linked to a water station yet.");
      }

      _workerId = worker['id'] as String;
      // Nullable now -- a driver between stations (left/removed, not yet
      // re-linked) has no current station.
      _stationId = worker['station_id'] as String?;

      final credentials = await _credentialService.fetchWorkerCredentials(_workerId!);
      _missingCredentialsCount = credentials.where((c) => c.status != PermitStatus.approved).length;

      if (_stationId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final station = await supabase
          .from('water_stations')
          .select('station_name, latitude, longitude')
          .eq('id', _stationId!)
          .maybeSingle();

      if (station != null) {
        _stationName = station['station_name'] ?? 'Water Station';
        _stationLocation = LatLng((station['latitude'] as num).toDouble(), (station['longitude'] as num).toDouble());
        // Drivers can't read the owner's profile, so the phone comes from
        // my_station_phone(); the old embed left "Call Station" with no
        // number to call.
        try {
          _stationPhone = (await supabase.rpc('my_station_phone') as String?) ?? '';
        } catch (_) {
          _stationPhone = '';
        }
      }

      final driverState = await supabase.from('driver_states').select('is_active').eq('worker_id', _workerId!).maybeSingle();
      _isOnDuty = driverState?['is_active'] as bool? ?? false;
      if (_isOnDuty) {
        // Resume broadcasting if the app was killed while on duty.
        await _requestLocationPermissionAndStartTracking();
      }

      await _fetchActiveDelivery();
    } catch (e) {
      logError('driver init', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _signOut() async {
    if (_isOnDuty && _workerId != null) {
      await _locationService.stopTracking(_workerId!);
    }
    await supabase.auth.signOut();
    // AuthGate (the app's root widget) reacts to the resulting auth-state
    // change and shows LoginScreen itself -- just pop back to reveal it,
    // don't push a new LoginScreen route on top of it.
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Returns whether GPS broadcasting actually started. Every early-return
  /// case (location services off, permission denied, no linked station)
  /// used to leave the ON-DUTY switch showing "Broadcasting GPS" while
  /// nothing was actually being sent -- the caller now only flips the
  /// switch on when this genuinely succeeds.
  Future<bool> _requestLocationPermissionAndStartTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    if (mounted) {
      await maybeShowLocationRationale(
        context,
        'GenTri: WASA needs your location so dispatch can route deliveries to you and customers can track you on the map while you\'re on duty.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    if (_stationId == null) return false;
    _locationService.startTracking(_workerId!, _stationId!);
    return true;
  }

  Future<void> _toggleOnDuty(bool value) async {
    if (_workerId == null) return;

    if (value) {
      final started = await _requestLocationPermissionAndStartTracking();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start GPS broadcasting -- check location permission/service and try again.')),
          );
        }
        return;
      }
    } else {
      await _locationService.stopTracking(_workerId!);
    }
    if (mounted) setState(() => _isOnDuty = value);
  }

  Future<void> _fetchActiveDelivery() async {
    if (!mounted) return;
    if (_stationId == null || _stationLocation == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await supabase.rpc('get_active_orders', params: {'p_station_id': _stationId});
      List<dynamic> activeOrders = List<dynamic>.from(response as List);

      if (activeOrders.isNotEmpty) {
        final stops = activeOrders
            .map((o) => {'lat': double.parse(o['lat'].toString()), 'lng': double.parse(o['lng'].toString())})
            .toList();

        // Road-following order and geometry. Never throws: if the routing
        // service is unreachable it returns a flagged straight-line estimate,
        // which the map labels rather than passing off as a real route.
        final plan = await _routeService.planRoute(
          _stationLocation!,
          [for (final s in stops) LatLng(s['lat']!, s['lng']!)],
        );
        if (plan.sequence.length == activeOrders.length) {
          activeOrders = plan.sequence.map((index) => activeOrders[index]).toList();
        }

        final currentOrder = activeOrders.first;

        final orderDetails = await supabase
            .from('orders')
            .select('status, total_amount, guest_name, guest_phone, customer_phone, jug_exchange_origin_station_id')
            .eq('id', currentOrder['id'])
            .maybeSingle();

        // Drivers can't read customers' profiles, so a profiles(...) embed
        // came back empty and every delivery said "Water Customer".
        // order_customer_contact returns just the name and phone, to the
        // assigned driver only.
        String custName = 'Water Customer';
        String custPhone = orderDetails?['customer_phone']?.toString() ?? orderDetails?['guest_phone']?.toString() ?? '';
        if (orderDetails?['guest_name'] != null) custName = orderDetails!['guest_name'].toString();
        try {
          final contact = await supabase.rpc('order_customer_contact', params: {'p_order_id': currentOrder['id']});
          if (contact is List && contact.isNotEmpty) {
            final c = contact.first as Map;
            if ((c['full_name'] ?? '').toString().trim().isNotEmpty) custName = c['full_name'].toString();
            if ((c['phone_number'] ?? '').toString().trim().isNotEmpty) custPhone = c['phone_number'].toString();
          }
        } catch (_) {
          // Keep the fallback; the delivery itself still works.
        }

        if (mounted) {
          setState(() {
            _orderedStops = List<Map<String, dynamic>>.from(activeOrders);
            _routePoints = plan.points;
            _routeApproximate = plan.isApproximate;
            _routeSummary = plan.summary;
            _currentActiveOrder = {
              ...currentOrder,
              'status': orderDetails?['status'] ?? 'assigned',
              'jug_exchange_origin_station_id': orderDetails?['jug_exchange_origin_station_id'],
            };
            _destination = LatLng(
              double.parse(currentOrder['lat'].toString()),
              double.parse(currentOrder['lng'].toString()),
            );
            _totalAmount = double.parse((orderDetails?['total_amount'] ?? 0).toString());
            _customerName = custName;
            _customerPhone = custPhone;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _currentActiveOrder = null;
            _orderedStops = [];
            _routePoints = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      logError('driver fetch', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber, String targetName) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No phone number available for $targetName.')),
      );
      return;
    }
    await callPhone(context, phoneNumber);
  }

  /// Metres from the phone to the drop-off pin, or null when the position
  /// can't be had quickly (no signal, GPS off, permission refused). Never
  /// waits more than a few seconds.
  Future<double?> _metresFromDropOff() async {
    final destination = _destination;
    if (destination == null) return null;
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 4)),
      );
    } catch (_) {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (position == null) return null;
    return Geolocator.distanceBetween(position.latitude, position.longitude, destination.latitude, destination.longitude);
  }

  /// Completing far from the pin asks first, so a delivery isn't marked done
  /// by mistake from the station or the road. It never blocks: a driver with
  /// no signal, or whose customer met them down the street, can still finish.
  Future<void> _confirmThenComplete() async {
    if (_currentActiveOrder == null) return;
    final warning = farFromDropOffWarning(await _metresFromDropOff());
    if (warning != null && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Far from the drop-off'),
          content: Text(warning),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not yet')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Mark delivered anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (mounted) await _showCompletionDialog();
  }

  Future<void> _showCompletionDialog() async {
    if (_currentActiveOrder == null) return;

    // Empties only come back on a refill of a returnable jug. The field used
    // to show for every order and default to 1, so a bottle order or a new
    // jug purchase was logged as having returned an empty.
    final order = _currentActiveOrder!;
    final expectsEmpties = expectsEmptyContainers(
      productKind: order['product_kind'] as String?,
      containerCode: order['jug_type'] as String?,
      isReturnable: order['is_returnable'] as bool?,
    );
    final quantity = (order['jugs_ordered'] as num?)?.toInt() ?? 1;
    final TextEditingController emptyJugsController = TextEditingController(text: expectsEmpties ? '$quantity' : '0');
    // Deliberately starts unset (null), not defaulted to true -- the driver
    // must explicitly confirm whether cash was actually collected.
    bool? paymentCollected;

    // Only relevant if the customer declared a jug exchange at order time --
    // the driver is the one actually looking at the jug, so they confirm or
    // correct it here rather than trusting the order-time guess blindly.
    final declaredOrigin = _currentActiveOrder!['jug_exchange_origin_station_id'] as String?;
    List<Map<String, dynamic>> otherStations = [];
    Map<String, String> otherStationNames = {};
    String? jugOrigin = declaredOrigin;
    bool noJugExchange = false;
    if (declaredOrigin != null && _stationId != null) {
      try {
        otherStations = await _jugService.fetchOtherStations(_stationId!);
        otherStationNames = {for (final s in otherStations) s['id'] as String: s['station_name'] as String};
      } catch (e) {
        logError('jug origin stations', e);
      }
    }
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: driverPalette.surface,
          titleTextStyle: TextStyle(color: driverPalette.text, fontSize: 18, fontWeight: FontWeight.bold),
          title: const Text('Complete Delivery & Return'),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expectsEmpties
                    ? 'Log the returned empty jugs and confirm cash collection before finalizing.'
                    : 'Confirm cash collection before finalizing.',
                style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.7)),
              ),
              if (expectsEmpties) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: emptyJugsController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: driverPalette.text),
                  decoration: InputDecoration(
                    labelText: 'Empty Jugs Collected',
                    labelStyle: TextStyle(color: driverPalette.text.withValues(alpha: 0.7)),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (declaredOrigin != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Customer said this jug is from ${otherStationNames[declaredOrigin] ?? 'another station'}. Confirm or correct:',
                  style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: noJugExchange,
                  onChanged: (v) => setDialogState(() => noJugExchange = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: driverPalette.onDuty,
                  title: Text('No jug was actually exchanged', style: TextStyle(color: driverPalette.text, fontSize: 16)),
                ),
                if (!noJugExchange)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: jugOrigin,
                    isDense: true,
                    dropdownColor: driverPalette.surface,
                    style: TextStyle(color: driverPalette.text, fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: "Jug's home station",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      if (jugOrigin != null && !otherStations.any((s) => s['id'] == jugOrigin))
                        DropdownMenuItem(value: jugOrigin, child: Text(otherStationNames[jugOrigin] ?? 'Declared station', overflow: TextOverflow.ellipsis)),
                      ...otherStations.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['station_name'] as String, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setDialogState(() => jugOrigin = v),
                  ),
              ],
              const SizedBox(height: 16),
              RadioGroup<bool>(
                groupValue: paymentCollected,
                onChanged: (val) => setDialogState(() => paymentCollected = val),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      title: Text('Cash was collected', style: TextStyle(color: driverPalette.text)),
                      value: true,
                      activeColor: driverPalette.onDuty,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      title: Text('Cash was NOT collected', style: TextStyle(color: driverPalette.text)),
                      value: false,
                      activeColor: driverPalette.alert,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: driverPalette.text.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: driverPalette.onDuty),
              onPressed: paymentCollected == null
                  ? null
                  : () {
                      final int emptyJugs = int.tryParse(emptyJugsController.text) ?? 0;
                      Navigator.pop(context);
                      _finalizeDelivery(
                        emptyJugs,
                        paymentCollected!,
                        jugExchangeOriginStationId: noJugExchange ? null : jugOrigin,
                        noJugExchange: noJugExchange,
                      );
                    },
              child: const Text('Confirm & Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  /// Hands the drop-off to a real navigation app. The in-app map shows the
  /// planned route, but a driver on the road needs turn-by-turn: Google Maps
  /// navigation first, then its web directions, then any app that handles a
  /// geo: point.
  Future<void> _navigateToDropOff() async {
    final destination = _destination;
    if (destination == null) return;
    final lat = destination.latitude;
    final lng = destination.longitude;

    for (final uri in [
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng(Delivery)'),
    ]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Try the next one -- a phone without Google Maps still has a browser.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app could be opened on this phone.')),
      );
    }
  }

  /// Reasons a driver can pick without typing, which is what they'll want
  /// at a doorstep. "Other" asks for a few words.
  static const _failureReasons = [
    'Nobody was home',
    'Wrong or incomplete address',
    'Customer refused the order',
    'Customer could not be reached by phone',
  ];

  Future<void> _reportFailedDelivery() async {
    if (_currentActiveOrder == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _FailedDeliveryDialog(reasons: _failureReasons),
    );
    if (reason == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _orderService.reportFailedDelivery(_currentActiveOrder!['id'] as String, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reported. The order is back with your station to reassign.')),
      );
      _fetchActiveDelivery();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _startDelivery() async {
    if (_currentActiveOrder == null) return;
    try {
      await _orderService.startDelivery(_currentActiveOrder!['id'] as String);
      _fetchActiveDelivery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  Future<void> _finalizeDelivery(
    int emptyJugsCollected,
    bool paymentCollected, {
    String? jugExchangeOriginStationId,
    bool noJugExchange = false,
  }) async {
    setState(() => _isLoading = true);
    try {
      await _orderService.completeDelivery(
        _currentActiveOrder!['id'] as String,
        emptyJugsReturned: emptyJugsCollected,
        paymentCollected: paymentCollected,
        jugExchangeOriginStationId: jugExchangeOriginStationId,
        noJugExchange: noJugExchange,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery Completed!'), backgroundColor: BrandStatus.success),
        );
        _fetchActiveDelivery();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    driverPalette = DriverPalette.of(context);
    return Scaffold(
      backgroundColor: driverPalette.background,
      appBar: AppBar(
        // Five icons left the title as "Driver ..." on a phone. The two used
        // most stay; the rest are under the menu.
        title: Text('Driver Dashboard',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: driverPalette.text, fontWeight: FontWeight.bold)),
        backgroundColor: driverPalette.surface,
        actions: [
          const NotificationBell(),
          IconButton(
            icon: Icon(Icons.person, color: driverPalette.text),
            tooltip: 'Driver Profile',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverProfileScreen()));
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: driverPalette.text),
            onSelected: (v) {
              switch (v) {
                case 'refresh':
                  _fetchActiveDelivery();
                case 'board':
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const BulletinBoardScreen()));
                case 'signout':
                  _signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh deliveries'))),
              PopupMenuItem(value: 'board', child: ListTile(leading: Icon(Icons.campaign), title: Text('Bulletin Board'))),
              PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign Out'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_missingCredentialsCount > 0) _buildCredentialsBanner(),
          _buildOnDutyBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stationId == null
                    ? _buildNoStationState()
                    : _currentActiveOrder == null
                        ? _buildEmptyState()
                        // Landscape (a phone in a windscreen cradle) puts the
                        // map and the delivery card side by side.
                        : DeliveryPanelLayout(
                            map: _buildMap(),
                            details: _buildDeliveryDetails(),
                            actions: _buildDeliveryActions(),
                            background: driverPalette.surface,
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsBanner() {
    return Material(
      color: AppColors.pendingClearance.withValues(alpha: 0.15),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverProfileScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.pendingClearance),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Action needed: submit your Government ID and Driver\'s License to complete WASA clearance.',
                  style: TextStyle(color: driverPalette.text, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 14, color: driverPalette.text),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoStationState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 80, color: driverPalette.text.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Not currently linked to a station.', style: TextStyle(fontSize: 18, color: driverPalette.text)),
            const SizedBox(height: 8),
            Text('Join a station from your profile to start receiving deliveries.', style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.7))),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverProfileScreen())),
              child: const Text('Go to Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnDutyBar() {
    return Container(
      width: double.infinity,
      color: _isOnDuty ? driverPalette.onDuty.withValues(alpha: 0.15) : driverPalette.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: _isOnDuty ? driverPalette.onDuty : driverPalette.offDuty, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isOnDuty ? 'ON DUTY — Broadcasting GPS' : 'OFF DUTY',
              style: TextStyle(
                color: _isOnDuty ? driverPalette.onDuty : driverPalette.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Switch(
            value: _isOnDuty,
            activeThumbColor: driverPalette.onDuty,
            onChanged: _toggleOnDuty,
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_destination == null || _stationLocation == null) {
      return Center(child: Text('Map loading...', style: TextStyle(color: driverPalette.text)));
    }

    final markers = <Marker>[
      Marker(
        point: _stationLocation!,
        width: 44,
        height: 44,
        child: const _MapPin(color: Colors.blue, icon: Icons.store),
      ),
      for (var i = 0; i < _orderedStops.length; i++)
        Marker(
          point: LatLng(double.parse(_orderedStops[i]['lat'].toString()), double.parse(_orderedStops[i]['lng'].toString())),
          width: 44,
          height: 44,
          child: _MapPin(color: i == 0 ? Colors.red : Colors.orange, icon: Icons.local_shipping),
        ),
    ];

    return FlutterMap(
      options: MapOptions(initialCenter: _destination!, initialZoom: 15),
      children: [
        const AppMapTiles(),
        if (_routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: Colors.blueAccent,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        RouteStatusBanner(isApproximate: _routeApproximate, summary: _routeSummary, onDark: true),
        const AppMapAttribution(showRoutingCredit: true),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 80, color: driverPalette.text.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text('No active deliveries right now.', style: TextStyle(fontSize: 18, color: driverPalette.text)),
          const SizedBox(height: 8),
          Text('Waiting for the station to assign an order...', style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildDeliveryDetails() {
    final shortId = _currentActiveOrder!['id'].toString().substring(0, 6).toUpperCase();
    final isEnRoute = _currentActiveOrder!['status'] == 'active';

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #$shortId', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: driverPalette.text)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Deliver to: $_customerName',
                            style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.8), fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Call customer',
                          onPressed: () => _makePhoneCall(_customerPhone, 'Customer'),
                          icon: Icon(Icons.phone, size: 22, color: driverPalette.onDuty),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  // Reuses the same status colors the customer-facing
                  // screens already use for these exact statuses (blue =
                  // "Driver Assigned", indigo = "Out for Delivery") instead
                  // of introducing new ad hoc colors that don't match.
                  color: isEnRoute ? Colors.indigo : Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(isEnRoute ? 'EN ROUTE' : 'ASSIGNED', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          Divider(height: 24, thickness: 1, color: driverPalette.text.withValues(alpha: 0.7)),
          // Wraps: "Call Station" drops under the name on a narrow phone
          // rather than squeezing it.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store, color: Colors.blueGrey, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text('Station: $_stationName', style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.8)))),
                ],
              ),
              TextButton.icon(
                onPressed: () => _makePhoneCall(_stationPhone, 'Water Station'),
                icon: Icon(Icons.phone, size: 18, color: driverPalette.onDuty),
                label: Text('Call Station', style: TextStyle(fontSize: 16, color: driverPalette.onDuty)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            Icons.water_drop,
            'Payload:',
            describeOrderLine(
              quantity: (_currentActiveOrder!['jugs_ordered'] as num).toInt(),
              waterType: _currentActiveOrder!['water_type'] as String? ?? '',
              containerCode: _currentActiveOrder!['jug_type'] as String?,
              containerLabelOverride: _currentActiveOrder!['container_label'] as String?,
              productKind: _currentActiveOrder!['product_kind'] as String?,
            ),
          ),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.payments, 'Collect:', formatPeso(_totalAmount)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _destination == null ? null : _navigateToDropOff,
            icon: Icon(Icons.navigation_outlined, size: 20, color: driverPalette.onDuty),
            label: Text('NAVIGATE', style: TextStyle(fontWeight: FontWeight.bold, color: driverPalette.onDuty)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: driverPalette.onDuty),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
    );
  }

  /// START / COMPLETE / COULDN'T DELIVER, pinned under the scrolling details.
  Widget _buildDeliveryActions() {
    final isEnRoute = _currentActiveOrder!['status'] == 'active';
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // While still just ASSIGNED, Start Delivery is the filled/primary
          // action and Complete Delivery is outlined/secondary -- a nudge
          // toward the intended order without blocking a driver who skips
          // straight to completing (still fully allowed server-side).
          if (!isEnRoute) ...[
            ElevatedButton.icon(
              onPressed: _startDelivery,
              icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
              label: const Text('START DELIVERY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: driverPalette.onDuty,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _confirmThenComplete,
              icon: const Icon(Icons.check_circle, size: 24, color: Colors.green),
              label: const Text('COMPLETE DELIVERY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.green),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else
            ElevatedButton.icon(
              onPressed: _confirmThenComplete,
              icon: const Icon(Icons.check_circle, size: 32, color: Colors.white),
              label: const Text('COMPLETE DELIVERY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          const SizedBox(height: 4),
          // Quiet on purpose: the expected path is completing the delivery.
          TextButton.icon(
            onPressed: _reportFailedDelivery,
            icon: Icon(Icons.report_gmailerrorred_outlined, color: driverPalette.alert),
            label: Text("COULDN'T DELIVER", style: TextStyle(fontWeight: FontWeight.bold, color: driverPalette.alert)),
          ),
        ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.blueGrey, size: 22),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 16, color: driverPalette.text.withValues(alpha: 0.8))),
        const SizedBox(width: 12),
        // Takes the rest of the line and wraps, right-aligned, instead of
        // pushing past the edge ("2 × Slim 5-gal · Purified" at large text).
        Expanded(
          child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: driverPalette.text)),
        ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

/// Picks why a delivery couldn't be made: a few common reasons as one tap,
/// or "Other" with a short note. Returns the reason, or null if cancelled.
class _FailedDeliveryDialog extends StatefulWidget {
  const _FailedDeliveryDialog({required this.reasons});

  final List<String> reasons;

  @override
  State<_FailedDeliveryDialog> createState() => _FailedDeliveryDialogState();
}

class _FailedDeliveryDialogState extends State<_FailedDeliveryDialog> {
  String? _selected;
  final _other = TextEditingController();
  static const _otherKey = '__other__';

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _reason {
    if (_selected == null) return null;
    if (_selected == _otherKey) {
      final t = _other.text.trim();
      return t.isEmpty ? null : t;
    }
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Couldn't deliver"),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _selected,
          onChanged: (v) => setState(() => _selected = v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The order goes back to your station so it can be reassigned. The customer is told the reason.'),
              const SizedBox(height: 8),
              for (final r in widget.reasons) RadioListTile<String>(value: r, title: Text(r), contentPadding: EdgeInsets.zero),
              const RadioListTile<String>(value: _otherKey, title: Text('Other'), contentPadding: EdgeInsets.zero),
              if (_selected == _otherKey)
                TextField(
                  controller: _other,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'What happened?'),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
          child: const Text('Report'),
        ),
      ],
    );
  }
}
