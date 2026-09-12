import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/customer_address.dart';
import '../../models/product.dart';
import '../../models/station.dart';
import '../../services/address_service.dart';
import '../../providers/app_state.dart';
import '../../services/nearby_service.dart';
import '../../services/order_service.dart';
import '../../services/product_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'addresses_screen.dart';
import 'order_confirmation_screen.dart';
import 'track_order_screen.dart';
import '../app_route.dart';
import '../../widgets/app_map_tiles.dart';
import '../../utils/error_text.dart';

/// Most a single order may contain. Mirrors v_max_qty in insert_quick_order
/// (supabase/patch_product_catalog.sql) so the form says so before the
/// server has to.
const kMaxOrderQuantity = 50;

/// What a customer can pick at a station: available products, in containers
/// the association still offers, matching the water-type filter if one is
/// set. Top-level so the rule is unit-testable.
List<StationProduct> orderableProducts(
  List<StationProduct> products,
  Map<String, ContainerType> activeContainers, {
  String? waterType,
}) {
  return products
      .where((p) =>
          p.isAvailable &&
          activeContainers.containsKey(p.containerCode) &&
          (waterType == null || p.waterType == waterType))
      .toList();
}

/// What "Order again" carries over from a past order. [unitPrice] is the
/// price that order was charged, so the form can say when it has changed.
class OrderPrefill {
  const OrderPrefill({
    required this.stationId,
    required this.productId,
    required this.quantity,
    this.unitPrice,
  });

  final String stationId;
  final String productId;
  final int quantity;
  final double? unitPrice;
}

/// Quick-order form for the Public Consumer Portal. Placing an order
/// requires a signed-in customer account (public_consumer membership,
/// registration_screen.dart) -- browsing/bulletin stay no-login, but
/// ordering doesn't, so a customer's orders are tied to a real account
/// instead of device-local guest state. Logged-out visitors see a gate
/// instead of the form (see _OrderLoginGate below).
///
/// The customer picks one of the station's products (water type, container,
/// refill or new). The price shown is a preview; the server computes the
/// amount actually stored on the order.
class QuickOrderScreen extends ConsumerStatefulWidget {
  const QuickOrderScreen({super.key, this.prefill});

  /// Set by "Order again" (my_orders_screen.dart) to reopen this form on the
  /// same station, product and quantity.
  final OrderPrefill? prefill;

  @override
  ConsumerState<QuickOrderScreen> createState() => _QuickOrderScreenState();
}

class _QuickOrderScreenState extends ConsumerState<QuickOrderScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _orderService = OrderService(SupabaseService.instance);
  final _productService = ProductService(SupabaseService.instance);
  final _nearbyService = NearbyService();
  double? _userLat;
  double? _userLng;

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _jugCountController = TextEditingController(text: '1');

  static const _initialCenter = LatLng(14.3868, 120.8817);

  final _addressService = AddressService(SupabaseService.instance);
  final _mapController = MapController();
  List<CustomerAddress> _addresses = [];
  String? _selectedAddressId;

  LatLng? _selectedLocation;
  String? _waterTypeFilter;

  /// Shown when "Order again" can't reproduce the order exactly.
  String? _prefillNotice;
  DateTime? _scheduledFor;
  bool _isJugExchange = false;
  String? _jugExchangeOriginStationId;

  bool _isLoading = false;
  bool _isFetchingStations = true;
  String? _fetchError;

  List<PublicStation> _availableStations = [];
  String? _selectedStationId;
  bool _hasInitializedForSession = false;

  // Products are loaded per station on demand and cached; containers once.
  List<ContainerType> _containers = [];
  final Map<String, List<StationProduct>> _productsByStation = {};
  bool _isLoadingProducts = false;
  String? _productsError;
  String? _selectedProductId;

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
      _loadAddresses();
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
    try {
      final row = await Supabase.instance.client.from('profiles').select('phone_number').eq('id', userId).maybeSingle();
      final phone = row?['phone_number'] as String?;
      // Only prefill if the field is still untouched -- this fetch is async,
      // so without this check it could clobber a phone number the customer
      // already started typing while it was in flight.
      if (phone != null && phone.isNotEmpty && mounted && _phoneController.text.isEmpty) {
        setState(() => _phoneController.text = phone);
      }
    } catch (_) {
      // Best-effort convenience prefill -- silently skip on failure rather
      // than surfacing an error for a non-critical field.
    }
  }

  /// Saved addresses, with the default pre-selected so the common case --
  /// ordering to the same house every week -- needs no map at all.
  Future<void> _loadAddresses() async {
    try {
      final addresses = await _addressService.fetchAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        final preferred = preferredAddress(addresses);
        if (preferred != null && _selectedLocation == null) {
          _selectedAddressId = preferred.id;
          _selectedLocation = LatLng(preferred.latitude, preferred.longitude);
        }
      });
      final location = _selectedLocation;
      if (location != null) {
        // The map is built by now; centring it on the saved pin saves the
        // customer hunting for their own street.
        try {
          _mapController.move(location, 16);
        } catch (_) {}
      }
    } catch (_) {
      // Saved addresses are a convenience; the map still works without them.
    }
  }

  void _useAddress(CustomerAddress address) {
    setState(() {
      _selectedAddressId = address.id;
      _selectedLocation = LatLng(address.latitude, address.longitude);
    });
    try {
      _mapController.move(LatLng(address.latitude, address.longitude), 16);
    } catch (_) {}
  }

  Future<void> _saveCurrentPin() async {
    final location = _selectedLocation;
    if (location == null) return;
    final saved = await Navigator.push<bool>(
      context,
      appRoute(AddressEditorScreen(initialPoint: location, isFirst: _addresses.isEmpty)),
    );
    if (saved == true) await _loadAddresses();
  }

  /// A station with no products has a derived "from" price of 0 and can't
  /// take orders (insert_quick_order refuses it).
  bool _hasProducts(PublicStation s) => s.pricePerJug > 0;

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
        final prefill = widget.prefill;
        setState(() {
          _availableStations = stations;
          if (prefill != null && stations.any((s) => s.id == prefill.stationId)) {
            _selectedStationId = prefill.stationId;
            _selectedProductId = prefill.productId;
            _jugCountController.text = '${prefill.quantity}';
          } else if (stations.isNotEmpty) {
            _selectedStationId =
                stations.firstWhere((s) => s.isOrderable && _hasProducts(s), orElse: () => stations.first).id;
            if (prefill != null) _prefillNotice = "That station isn't listed any more. Pick another one.";
          }
          _isFetchingStations = false;
        });
        if (_selectedStationId != null) _loadProductsFor(_selectedStationId!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Could not load water stations. ${describeError(e)}';
          _isFetchingStations = false;
        });
      }
    }
  }

  Future<void> _loadProductsFor(String stationId, {bool force = false}) async {
    if (!force && _productsByStation.containsKey(stationId)) return;
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });
    try {
      if (_containers.isEmpty) _containers = await _productService.fetchContainerTypes();
      final products = await _productService.fetchStationProducts(stationId);
      if (!mounted) return;
      setState(() {
        _productsByStation[stationId] = products;
        _isLoadingProducts = false;
        _prefillNotice ??= _noticeForPrefill(stationId, products);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _productsError = "Could not load this station's products.";
        _isLoadingProducts = false;
      });
    }
  }

  /// "Order again" is a convenience, not a promise: the product may be gone
  /// or cost something else now, and the customer should see that before
  /// they order rather than after.
  String? _noticeForPrefill(String stationId, List<StationProduct> products) {
    final prefill = widget.prefill;
    if (prefill == null || stationId != prefill.stationId) return null;
    StationProduct? previous;
    for (final product in products) {
      if (product.id == prefill.productId) previous = product;
    }
    if (previous == null || !previous.isAvailable) {
      return "What you ordered last time isn't available any more. Pick something else below.";
    }
    if (prefill.unitPrice != null && prefill.unitPrice != previous.price) {
      return 'The price changed since your last order: ${formatPeso(prefill.unitPrice!)} → ${formatPeso(previous.price)}.';
    }
    return null;
  }

  Map<String, ContainerType> get _containerByCode => {for (final c in _containers) c.code: c};

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

  List<StationProduct> get _productsForSelectedStation {
    final station = _selectedStation;
    if (station == null) return const [];
    return orderableProducts(_productsByStation[station.id] ?? const [], _containerByCode, waterType: _waterTypeFilter);
  }

  /// The chosen product, or the first one on offer when nothing is chosen
  /// yet (or the previous choice no longer applies).
  StationProduct? get _selectedProduct {
    final products = _productsForSelectedStation;
    for (final p in products) {
      if (p.id == _selectedProductId) return p;
    }
    return products.isEmpty ? null : products.first;
  }

  String _productTitle(StationProduct p) {
    final label = _containerByCode[p.containerCode]?.label ?? p.containerCode;
    return p.kind == ProductKind.refill ? '$label refill' : '$label (new)';
  }

  /// An empty only gets exchanged on a refill of a returnable container.
  bool _canExchange(StationProduct p, PublicStation station) =>
      station.offersJugExchange &&
      p.kind == ProductKind.refill &&
      (_containerByCode[p.containerCode]?.isReturnable ?? false);

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
    final product = _selectedProduct;
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
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choose what you'd like to order.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final int quantity = int.parse(_jugCountController.text.trim());
      final preview = previewOrderPrice(unitPrice: product.price, quantity: quantity, deliveryFee: station.deliveryFee);

      final orderId = await _orderService.insertQuickOrder(
        stationId: station.id,
        lat: _selectedLocation!.latitude,
        lng: _selectedLocation!.longitude,
        jugsOrdered: quantity,
        waterType: product.waterType,
        subtotal: preview.subtotal,
        deliveryFee: station.deliveryFee,
        totalAmount: preview.total,
        guestPhone: _phoneController.text.trim(),
        clientRequestId: _clientRequestId,
        scheduledFor: _scheduledFor,
        jugType: product.containerCode,
        jugExchangeOriginStationId: _isJugExchange && _canExchange(product, station) ? _jugExchangeOriginStationId : null,
        productId: product.id,
      );

      // Show the total the server stored rather than this screen's
      // arithmetic: the server prices the order itself, and the two differ
      // if the station changed a price after this screen loaded it.
      var total = preview.total;
      try {
        final row = await Supabase.instance.client.from('orders').select('total_amount').eq('id', orderId).single();
        total = (row['total_amount'] as num).toDouble();
      } catch (_) {
        // Keep the preview; the order itself has been placed.
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          appRoute(OrderConfirmationScreen(
              orderId: orderId,
              stationName: station.stationName,
              totalAmount: total,
              guestPhone: _phoneController.text.trim(),
            ),
          ),
        );
      }
    } on PostgrestException catch (e) {
      // The server's rejections ("This station does not offer ...") are
      // written for customers, so they're shown as-is.
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place the order. ${describeError(e)}')));
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
    final product = _selectedProduct;

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
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _selectedLocation ?? _initialCenter,
                          initialZoom: _selectedLocation == null ? 14 : 16,
                          onTap: (tapPosition, point) => setState(() {
                            _selectedLocation = point;
                            // A pin dropped by hand is no longer one of the
                            // saved addresses.
                            _selectedAddressId = null;
                          }),
                        ),
                        children: [
                          const AppMapTiles(),
                          if (_selectedLocation != null)
                            MarkerLayer(markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 40,
                                height: 40,
                                child: const MapPin(kind: MapPinKind.deliveryAddress),
                              ),
                            ]),
                          const AppMapAttribution(),
                        ],
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
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
                        if (_prefillNotice != null) ...[
                          _buildNotice(_prefillNotice!),
                          const SizedBox(height: 12),
                        ],
                        _buildAddressPicker(),
                        DropdownButtonFormField<String?>(
                          initialValue: _waterTypeFilter,
                          decoration: const InputDecoration(labelText: 'Water Type', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop_outlined)),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Any')),
                            for (final w in kWaterTypes) DropdownMenuItem(value: w, child: Text(waterTypeLabel(w))),
                          ],
                          onChanged: (val) => setState(() {
                            _waterTypeFilter = val;
                            _selectedProductId = null;
                            // Previously left _selectedStationId pointing at
                            // a station no longer in _filteredStations when
                            // the new filter matched zero stations -- the
                            // dropdown below then had a non-null value with
                            // no matching item, which throws at runtime.
                            if (_filteredStations.isEmpty) {
                              _selectedStationId = null;
                            } else if (!_filteredStations.any((s) => s.id == _selectedStationId)) {
                              _selectedStationId = _filteredStations.first.id;
                              _loadProductsFor(_selectedStationId!);
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
                                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    backgroundImage: s.photoUrl != null ? NetworkImage(s.photoUrl!) : null,
                                    child: s.photoUrl == null ? Icon(Icons.storefront, size: 12, color: Colors.grey.shade700) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(s.stationName, overflow: TextOverflow.ellipsis, style: TextStyle(color: s.isOrderable && _hasProducts(s) ? null : Colors.grey))),
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
                                  ] else if (!_hasProducts(s)) ...[
                                    const SizedBox(width: 6),
                                    Text('(no products yet)', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedStationId = val;
                              _selectedProductId = null;
                              _isJugExchange = false;
                              _jugExchangeOriginStationId = null;
                            });
                            if (val != null) _loadProductsFor(val);
                          },
                        ),
                        if (station != null) ...[
                          if (station.isColorumVerified)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(Icons.verified, size: 14, color: Colors.white),
                                  label: Text('WASA Verified', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  backgroundColor: Colors.green,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          const Text('What would you like?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          _buildProductPicker(station),
                          if (product != null && _canExchange(product, station)) ...[
                            const SizedBox(height: 4),
                            CheckboxListTile(
                              value: _isJugExchange,
                              onChanged: (v) => setState(() {
                                _isJugExchange = v ?? false;
                                if (!_isJugExchange) _jugExchangeOriginStationId = null;
                              }),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text("I'm returning an empty jug for exchange", style: TextStyle(fontSize: 13)),
                            ),
                            if (_isJugExchange) ...[
                              const Text('Whose station is the empty jug from?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String?>(
                                initialValue: _jugExchangeOriginStationId,
                                isDense: true,
                                decoration: const InputDecoration(
                                  labelText: "Jug's home station",
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(value: null, child: Text('${station.stationName} (this station)')),
                                  ..._availableStations
                                      .where((s) => s.id != station.id)
                                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.stationName, overflow: TextOverflow.ellipsis))),
                                ],
                                onChanged: (v) => setState(() => _jugExchangeOriginStationId = v),
                              ),
                            ],
                          ],
                          if (!station.isOrderable) ...[
                            const SizedBox(height: 8),
                            _buildNotice(
                              'This station is currently closed and not accepting orders. Please pick another station.',
                              isWarning: true,
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
                          decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder(), prefixIcon: Icon(Icons.water_drop)),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}), // keeps the price summary live
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 1) return 'Enter at least 1';
                            if (n > kMaxOrderQuantity) return 'At most $kMaxOrderQuantity per order';
                            return null;
                          },
                        ),
                        if (station != null && product != null) ...[
                          const SizedBox(height: 12),
                          _buildPriceSummary(station, product),
                        ],
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
                          onPressed: (_isLoading || station?.isOrderable == false || product == null) ? null : _submitOrder,
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

  Widget _buildAddressPicker() {
    final hasPin = _selectedLocation != null;
    if (_addresses.isEmpty && !hasPin) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Deliver to', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            if (_addresses.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await Navigator.push(context, appRoute(const AddressesScreen()));
                  await _loadAddresses();
                },
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Manage'),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final address in _addresses)
              ChoiceChip(
                label: Text(address.label),
                selected: address.id == _selectedAddressId,
                onSelected: (_) => _useAddress(address),
              ),
            if (_selectedAddressId == null && hasPin)
              InputChip(
                avatar: const Icon(Icons.push_pin, size: 16),
                label: const Text('Pin on the map'),
                selected: true,
                onSelected: (_) {},
                onDeleted: _saveCurrentPin,
                deleteIcon: const Icon(Icons.bookmark_add_outlined, size: 18),
                deleteButtonTooltipMessage: 'Save this pin as an address',
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildProductPicker(PublicStation station) {
    if (_isLoadingProducts && !_productsByStation.containsKey(station.id)) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator());
    }
    if (_productsError != null && !_productsByStation.containsKey(station.id)) {
      return Row(
        children: [
          Expanded(child: Text(_productsError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          TextButton(onPressed: () => _loadProductsFor(station.id, force: true), child: const Text('Retry')),
        ],
      );
    }
    final products = _productsForSelectedStation;
    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _buildNotice(_waterTypeFilter == null
            ? "This station hasn't listed any products yet. Please pick another station."
            : "This station doesn't sell ${waterTypeLabel(_waterTypeFilter!)} water. Pick another water type or station."),
      );
    }
    final selected = _selectedProduct;
    final grouped = groupProductsByWaterType(products, _containerByCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(waterTypeLabel(entry.key), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in entry.value)
                ChoiceChip(
                  label: Text('${_productTitle(p)} · ${formatPeso(p.price)}'),
                  selected: p.id == selected?.id,
                  onSelected: (_) => setState(() {
                    _selectedProductId = p.id;
                    if (!_canExchange(p, station)) {
                      _isJugExchange = false;
                      _jugExchangeOriginStationId = null;
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSummary(PublicStation station, StationProduct product) {
    final quantity = int.tryParse(_jugCountController.text.trim()) ?? 0;
    final preview = previewOrderPrice(unitPrice: product.price, quantity: quantity, deliveryFee: station.deliveryFee);
    Widget line(String label, String value, {bool bold = false}) {
      final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
      return Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          line('$quantity × ${_productTitle(product)}', formatPeso(preview.subtotal)),
          const SizedBox(height: 4),
          line('Delivery', station.deliveryFee == 0 ? 'Free' : formatPeso(station.deliveryFee)),
          const Divider(height: 16),
          line('Total due on delivery', formatPeso(preview.total), bold: true),
        ],
      ),
    );
  }

  Widget _buildNotice(String message, {bool isWarning = false}) {
    final color = isWarning ? Colors.redAccent : Colors.grey.shade800;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isWarning ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isWarning ? Colors.red.shade200 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12))),
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
                onPressed: () => Navigator.push(context, appRoute(const LoginScreen())),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                child: const Text('Login', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.push(context, appRoute(const RegistrationScreen())),
                child: const Text('Create Account'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(context, appRoute(const TrackOrderScreen())),
                child: const Text('Track a past guest order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
