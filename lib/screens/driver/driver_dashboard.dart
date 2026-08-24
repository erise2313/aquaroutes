import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/permit.dart';
import '../../services/location_service.dart';
import '../../services/route_optimization.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../utils/formatters.dart';
import '../public/bulletin_board_screen.dart';
import 'driver_profile_screen.dart';


class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final supabase = Supabase.instance.client;
  final LocationService _locationService = LocationService();
  final RouteOptimizationService _routeService = RouteOptimizationService();
  final _credentialService = WorkerCredentialService(SupabaseService.instance);

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
          .select('station_name, latitude, longitude, owner_profile_id, profiles!water_stations_owner_profile_id_fkey(phone_number)')
          .eq('id', _stationId!)
          .maybeSingle();

      if (station != null) {
        _stationName = station['station_name'] ?? 'Water Station';
        _stationLocation = LatLng((station['latitude'] as num).toDouble(), (station['longitude'] as num).toDouble());
        final ownerProfile = station['profiles'];
        if (ownerProfile is Map) {
          _stationPhone = ownerProfile['phone_number']?.toString() ?? '';
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
      debugPrint('Driver init error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  Future<void> _requestLocationPermissionAndStartTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _locationService.startTracking(_workerId!);
  }

  Future<void> _toggleOnDuty(bool value) async {
    if (_workerId == null) return;

    if (value) {
      await _requestLocationPermissionAndStartTracking();
    } else {
      await _locationService.stopTracking(_workerId!);
    }
    setState(() => _isOnDuty = value);
  }

  Future<void> _fetchActiveDelivery() async {
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

        try {
          final sequence = _routeService.computeStopSequence(
            {'lat': _stationLocation!.latitude, 'lng': _stationLocation!.longitude},
            stops,
          );
          if (sequence.length == activeOrders.length) {
            activeOrders = sequence.map((index) => activeOrders[index]).toList();
          }
        } catch (e) {
          debugPrint('Stop sequencing skipped: $e');
        }

        final currentOrder = activeOrders.first;

        final orderDetails = await supabase
            .from('orders')
            .select('total_amount, guest_name, guest_phone, customer_phone, profiles(full_name, phone_number)')
            .eq('id', currentOrder['id'])
            .maybeSingle();

        String custName = 'Water Customer';
        String custPhone = '';
        if (orderDetails != null) {
          final custProfile = orderDetails['profiles'];
          if (custProfile is Map && custProfile['full_name'] != null) {
            custName = custProfile['full_name'].toString();
            custPhone = custProfile['phone_number']?.toString() ?? '';
          } else if (orderDetails['guest_name'] != null) {
            custName = orderDetails['guest_name'].toString();
            custPhone = orderDetails['guest_phone']?.toString() ?? orderDetails['customer_phone']?.toString() ?? '';
          }
        }

        if (mounted) {
          setState(() {
            _orderedStops = List<Map<String, dynamic>>.from(activeOrders);
            _currentActiveOrder = currentOrder;
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
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Driver Fetch Error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint('Could not launch phone dialer for $phoneNumber');
    }
  }

  void _showCompletionDialog() {
    if (_currentActiveOrder == null) return;

    final TextEditingController emptyJugsController = TextEditingController(text: '1');
    // Deliberately starts unset (null), not defaulted to true -- the driver
    // must explicitly confirm whether cash was actually collected.
    bool? paymentCollected;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.driverSurface,
          titleTextStyle: const TextStyle(color: AppColors.driverText, fontSize: 18, fontWeight: FontWeight.bold),
          title: const Text('Complete Delivery & Return'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Log the returned empty jugs and confirm cash collection before finalizing.',
                style: TextStyle(fontSize: 13, color: AppColors.driverText.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emptyJugsController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.driverText),
                decoration: InputDecoration(
                  labelText: 'Empty Jugs Collected',
                  labelStyle: TextStyle(color: AppColors.driverText.withValues(alpha: 0.7)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              RadioGroup<bool>(
                groupValue: paymentCollected,
                onChanged: (val) => setDialogState(() => paymentCollected = val),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      title: const Text('Cash was collected', style: TextStyle(color: AppColors.driverText)),
                      value: true,
                      activeColor: AppColors.driverOnDuty,
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<bool>(
                      title: const Text('Cash was NOT collected', style: TextStyle(color: AppColors.driverText)),
                      value: false,
                      activeColor: AppColors.driverAlert,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppColors.driverText.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.driverOnDuty),
              onPressed: paymentCollected == null
                  ? null
                  : () {
                      final int emptyJugs = int.tryParse(emptyJugsController.text) ?? 0;
                      Navigator.pop(context);
                      _finalizeDelivery(emptyJugs, paymentCollected!);
                    },
              child: const Text('Confirm & Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizeDelivery(int emptyJugsCollected, bool paymentCollected) async {
    setState(() => _isLoading = true);
    try {
      await supabase.from('orders').update({
        'status': 'done',
        'empty_jugs_returned': emptyJugsCollected,
        'payment_collected': paymentCollected,
      }).eq('id', _currentActiveOrder!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery Completed!'), backgroundColor: Colors.green),
        );
        _fetchActiveDelivery();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.driverBackground,
      appBar: AppBar(
        title: const Text('Driver Dashboard', style: TextStyle(color: AppColors.driverText, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.driverSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: AppColors.driverText),
            tooltip: 'Driver Profile',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverProfileScreen()));
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.driverText), onPressed: _fetchActiveDelivery, tooltip: 'Refresh Queue'),
          IconButton(
            icon: const Icon(Icons.campaign, color: AppColors.driverText),
            tooltip: 'Bulletin Board',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const BulletinBoardScreen()));
            },
          ),
          IconButton(icon: const Icon(Icons.logout, color: AppColors.driverAlert), onPressed: _signOut, tooltip: 'Sign Out'),
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
                        : Column(
                            children: [
                              Expanded(flex: 5, child: _buildMap()),
                              Expanded(
                                flex: 4,
                                child: Container(
                                  decoration: const BoxDecoration(color: AppColors.driverSurface),
                                  child: _buildActiveDeliveryCard(),
                                ),
                              ),
                            ],
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
                  style: const TextStyle(color: AppColors.driverText, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.driverText),
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
            Icon(Icons.store_outlined, size: 80, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            const Text('Not currently linked to a station.', style: TextStyle(fontSize: 18, color: AppColors.driverText)),
            const SizedBox(height: 8),
            const Text('Join a station from your profile to start receiving deliveries.', style: TextStyle(fontSize: 14, color: Colors.grey)),
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
      color: _isOnDuty ? AppColors.driverOnDuty.withValues(alpha: 0.15) : AppColors.driverSurface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: _isOnDuty ? AppColors.driverOnDuty : AppColors.driverOffDuty, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isOnDuty ? 'ON DUTY — Broadcasting GPS' : 'OFF DUTY',
              style: TextStyle(
                color: _isOnDuty ? AppColors.driverOnDuty : AppColors.driverText,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Switch(
            value: _isOnDuty,
            activeThumbColor: AppColors.driverOnDuty,
            onChanged: _toggleOnDuty,
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_destination == null || _stationLocation == null) {
      return const Center(child: Text('Map loading...', style: TextStyle(color: AppColors.driverText)));
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
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ph.gentriwasa.aquaroute',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [_stationLocation!, ...markers.skip(1).map((m) => m.point)],
              color: Colors.blueAccent,
              strokeWidth: 4,
            ),
          ],
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_shipping_outlined, size: 80, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          const Text('No active deliveries right now.', style: TextStyle(fontSize: 18, color: AppColors.driverText)),
          const SizedBox(height: 8),
          const Text('Waiting for the station to assign an order...', style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActiveDeliveryCard() {
    final shortId = _currentActiveOrder!['id'].toString().substring(0, 6).toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #$shortId', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.driverText)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('Deliver to: $_customerName', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _makePhoneCall(_customerPhone, 'Customer'),
                        child: const Icon(Icons.phone, size: 22, color: AppColors.driverOnDuty),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade900, borderRadius: BorderRadius.circular(20)),
                child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1, color: Colors.grey),
          Row(
            children: [
              const Icon(Icons.store, color: Colors.blueGrey, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Station: $_stationName', style: const TextStyle(fontSize: 13, color: Colors.grey))),
              TextButton.icon(
                onPressed: () => _makePhoneCall(_stationPhone, 'Water Station'),
                icon: const Icon(Icons.phone, size: 18, color: AppColors.driverOnDuty),
                label: const Text('Call Station', style: TextStyle(fontSize: 13, color: AppColors.driverOnDuty)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(Icons.water_drop, 'Payload:', '${_currentActiveOrder!['jugs_ordered']} Jugs'),
          const SizedBox(height: 8),
          _buildDetailRow(Icons.payments, 'Collect:', formatPeso(_totalAmount)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showCompletionDialog,
            icon: const Icon(Icons.check_circle, size: 32, color: Colors.white),
            label: const Text('COMPLETE DELIVERY', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 22),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.driverText)),
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
