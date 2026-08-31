import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/station.dart';
import '../../providers/app_state.dart';
import '../../services/nearby_service.dart';
import '../../services/order_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'order_confirmation_screen.dart';
import 'track_order_screen.dart';

/// Quick-order form for the Public Consumer Portal. Placing an order
/// requires a signed-in customer account (public_consumer membership,
/// registration_screen.dart) -- browsing/bulletin stay no-login, but
/// ordering doesn't, so a customer's orders are tied to a real account
/// instead of device-local guest state. Logged-out visitors see a gate
/// instead of the form (see _OrderLoginGate below).
class QuickOrderScreen extends ConsumerStatefulWidget {
  const QuickOrderScreen({super.key});

  @override
  ConsumerState<QuickOrderScreen> createState() => _QuickOrderScreenState();
}

class _QuickOrderScreenState extends ConsumerState<QuickOrderScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _orderService = OrderService(SupabaseService.instance);
  final _nearbyService = NearbyService();
  double? _userLat;
  double? _userLng;

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _jugCountController = TextEditingController(text: '1');

  static const _initialCenter = LatLng(14.3868, 120.8817);

  LatLng? _selectedLocation;
  String? _waterTypeFilter;
  DateTime? _scheduledFor;

  bool _isLoading = false;
  bool _isFetchingStations = true;
  String? _fetchError;

  List<PublicStation> _availableStations = [];
  String? _selectedStationId;
  bool _hasInitializedForSession = false;

  // Idempotency key for this order attempt -- reused across manual retries
  // (e.g. after a network error) so a genuine retry-after-timeout can't
  // create a second order server-side; a fresh value is only generated
  // when this screen itself is recreated (a new order attempt), since
  // pushReplacement to OrderConfirmationScreen on success tears this
  // screen down entirely.
  final String _clientRequestId = _generateRequestId();

  static String _generateRequestId() {
    final rnd = Random.secure();
    return List<int>.generate(16, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void initState() {
    super.initState();
    if (Supabase.instance.client.auth.currentUser != null) {
      _initializeForSession();
    } else {
      _isFetchingStations = false;
    }
  }

  /// Called once from initState if already logged in, or lazily from
  /// build() (via ref.watch(authStateProvider) triggering a rebuild) the
  /// moment a previously-logged-out visitor signs in -- this widget lives
  /// inside PublicHomeScreen's IndexedStack, so it stays mounted across
  /// login/logout rather than being recreated, and initState alone would
  /// never re-fire.
  void _initializeForSession() {
    if (_hasInitializedForSession) return;
    _hasInitializedForSession = true;
    // Deferred to after this build completes -- _fetchStations calls
    // setState synchronously as its first statement, which isn't allowed
    // while build() is still running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchStations();
      _prefillContactPhone();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _jugCountController.dispose();
    super.dispose();
  }

  Future<void> _prefillContactPhone() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final row = await Supabase.instance.client.from('profiles').select('phone_number').eq('id', userId).maybeSingle();
    final phone = row?['phone_number'] as String?;
    // Only prefill if the field is still untouched -- this fetch is async,
    // so without this check it could clobber a phone number the customer
    // already started typing while it was in flight.
    if (phone != null && phone.isNotEmpty && mounted && _phoneController.text.isEmpty) {
      setState(() => _phoneController.text = phone);
    }
  }

  Future<void> _fetchStations() async {
    setState(() {
      _isFetchingStations = true;
      _fetchError = null;
    });
    try {
      var stations = await _stationService.fetchPublicStations();

      // Best-effort "near me" sort -- if location is unavailable/denied,
      // fall back to the unsorted list rather than blocking ordering on it.
      if (mounted) {
        await maybeShowLocationRationale(
          context,
          'GenTri: WASA can use your location to show and sort nearby water stations.',
        );
      }
      final position = await _nearbyService.getCurrentPositionOrNull();
      if (position != null) {
        stations = _nearbyService.sortByDistance(stations, position.latitude, position.longitude);
        _userLat = position.latitude;
        _userLng = position.longitude;
      }

      if (mounted) {
        setState(() {
          _availableStations = stations;
          if (stations.isNotEmpty) _selectedStationId = stations.firstWhere((s) => s.isOrderable, orElse: () => stations.first).id;
          _isFetchingStations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Could not load water stations: $e';
          _isFetchingStations = false;
        });
      }
    }
  }

  List<PublicStation> get _filteredStations {
    if (_waterTypeFilter == null) return _availableStations;
    return _availableStations.where((s) => s.offeredWaterTypes.contains(_waterTypeFilter)).toList();
  }

  PublicStation? get _selectedStation {
    try {
      return _availableStations.firstWhere((s) => s.id == _selectedStationId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickScheduledTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledFor ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledFor ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() => _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submitOrder() async {
    final station = _selectedStation;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (station == null || _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a station and drop a pin for your delivery address!')),
      );
      return;
    }
    if (!station.isOrderable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This station is currently closed and not accepting orders.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final int jugs = int.parse(_jugCountController.text.trim());
      final double subtotal = jugs * station.pricePerJug;
      final double total = subtotal + station.deliveryFee;

      // If the customer filtered by "Any" water type, don't just default to
      // 'purified' -- that could record an order for a type the chosen
      // station doesn't actually offer. Fall back to whatever the station
      // does offer instead.
      final waterType = _waterTypeFilter ?? (station.offeredWaterTypes.isNotEmpty ? station.offeredWaterTypes.first : 'purified');

      final orderId = await _orderService.insertQuickOrder(
        stationId: station.id,
        lat: _selectedLocation!.latitude,
        lng: _selectedLocation!.longitude,
        jugsOrdered: jugs,
        waterType: waterType,
        subtotal: subtotal,
        deliveryFee: station.deliveryFee,
        totalAmount: total,
        guestPhone: _phoneController.text.trim(),
        clientRequestId: _clientRequestId,
        scheduledFor: _scheduledFor,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OrderConfirmationScreen(
              orderId: orderId,
              stationName: station.stationName,
              totalAmount: total,
              guestPhone: _phoneController.text.trim(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authStateProvider); // reactivity trigger -- see _initializeForSession's doc comment
    if (Supabase.instance.client.auth.currentUser == null) {
      _hasInitializedForSession = false;
      return const _OrderLoginGate();
    }
    _initializeForSession();

    final station = _selectedStation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Water Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade700,
      ),
      body: _isFetchingStations
          ? const Center(child: CircularProgressIndicator())
          : _fetchError != null
          ? ErrorState(message: _fetchError!, onRetry: _fetchStations)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: _initialCenter,
                          initialZoom: 14,
                          onTap: (tapPosition, point) => setState(() => _selectedLocation = point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'ph.gentriwasa.aquaroute',
                          ),
                          if (_selectedLocation != null)
                            MarkerLayer(markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 40,
                                height: 40,
                                child: const MapPin(kind: MapPinKind.deliveryAddress),
                              ),
                            ]),
                        ],
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.white.withValues(alpha: 0.9),
                          child: const Text(
                            'Tap the map to set your delivery address',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String?>(
                          initialValue: _waterTypeFilter,
                          decoration: const InputDecoration(labelText: 'Water Type', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop_outlined)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Any')),
                            DropdownMenuItem(value: 'purified', child: Text('Purified')),
                            DropdownMenuItem(value: 'mineral', child: Text('Mineral')),
                            DropdownMenuItem(value: 'alkaline', child: Text('Alkaline')),
                          ],
                          onChanged: (val) => setState(() {
                            _waterTypeFilter = val;
                            if (_filteredStations.isNotEmpty && !_filteredStations.any((s) => s.id == _selectedStationId)) {
                              _selectedStationId = _filteredStations.first.id;
                            }
                          }),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedStationId,
                          decoration: const InputDecoration(labelText: 'Select Water Station', border: OutlineInputBorder(), prefixIcon: Icon(Icons.storefront)),
                          items: _filteredStations.map((s) {
                            return DropdownMenuItem<String>(
                              value: s.id,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: s.photoUrl != null ? NetworkImage(s.photoUrl!) : null,
                                    child: s.photoUrl == null ? Icon(Icons.storefront, size: 12, color: Colors.grey.shade700) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(s.stationName, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.isOrderable ? null : Colors.grey))),
                                  if (s.isColorumVerified) const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Icon(Icons.verified, size: 16, color: Colors.green),
                                  ),
                                  if (_userLat != null && _userLng != null) ...[
                                    const SizedBox(width: 6),
                                    Text('· ${_nearbyService.formatDistance(_nearbyService.distanceKm(_userLat!, _userLng!, s))}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                  ],
                                  if (!s.isOrderable) ...[
                                    const SizedBox(width: 6),
                                    const Text('(Closed)', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedStationId = val),
                        ),
                        if (station != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Rates: ${formatPeso(station.pricePerJug)}/jug · ${formatPeso(station.deliveryFee)} delivery',
                                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (station.isColorumVerified)
                                const Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(Icons.verified, size: 14, color: Colors.white),
                                  label: Text('WASA Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  backgroundColor: Colors.green,
                                ),
                            ],
                          ),
                          if (station.offeredJugTypes.isNotEmpty || station.offersJugExchange) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final jugType in station.offeredJugTypes)
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(jugType == 'slim_5gal' ? 'Slim 5-gal' : 'Round 5-gal', style: const TextStyle(fontSize: 11)),
                                  ),
                                if (station.offersJugExchange)
                                  const Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: Icon(Icons.swap_horiz, size: 14),
                                    label: Text('Jug exchange accepted', style: TextStyle(fontSize: 11)),
                                  ),
                              ],
                            ),
                          ],
                          if (!station.isOrderable) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                              child: const Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(child: Text('This station is currently closed and not accepting orders. Please pick another station.', style: TextStyle(color: Colors.redAccent, fontSize: 12))),
                                ],
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Contact Number for This Delivery', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_outlined)),
                          validator: (v) {
                            final trimmed = v?.trim() ?? '';
                            if (trimmed.isEmpty) return 'Enter your phone number';
                            if (!RegExp(r'^[0-9+\-\s]{7,}$').hasMatch(trimmed)) return 'Enter a valid phone number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _jugCountController,
                          decoration: const InputDecoration(labelText: 'Number of Jugs', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop)),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 1) return 'Enter at least 1 jug';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('ASAP'), icon: Icon(Icons.bolt)),
                            ButtonSegment(value: true, label: Text('Scheduled'), icon: Icon(Icons.event)),
                          ],
                          selected: {_scheduledFor != null},
                          onSelectionChanged: (selection) async {
                            final wantsScheduled = selection.first;
                            if (!wantsScheduled) {
                              setState(() => _scheduledFor = null);
                              return;
                            }
                            await _pickScheduledTime();
                          },
                        ),
                        if (_scheduledFor != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Scheduled for ${_scheduledFor!.month}/${_scheduledFor!.day} at ${TimeOfDay.fromDateTime(_scheduledFor!).format(context)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(onPressed: _pickScheduledTime, child: const Text('Change')),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text('Cash on delivery only.', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: (_isLoading || station?.isOrderable == false) ? null : _submitOrder,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(vertical: 20)),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('PLACE ORDER', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Shown by QuickOrderScreen when no session exists -- placing an order
/// requires a customer account (see the class doc comment above).
class _OrderLoginGate extends StatelessWidget {
  const _OrderLoginGate();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Water Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping_outlined, size: 56, color: Colors.blue.shade700),
              const SizedBox(height: 16),
              const Text(
                'Log in or create a free account to place a water order.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Browsing the Bulletin Board and station map never requires an account -- only ordering does.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                child: const Text('Login', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                child: const Text('Create Account'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const TrackOrderScreen())),
                child: const Text('Track a past guest order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
