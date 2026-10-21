import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import 'location_picker_screen.dart';

/// How a station-entered order is placed (station_create_order,
/// patch_stations_members.sql).
enum StationOrderChannel { phone, walkIn }

/// What the dialog would charge: the server prices the order the same way,
/// so this is only for the owner to read back to the caller. Pure, so it is
/// unit-tested.
({double subtotal, double fee, double total}) stationOrderTotal({
  required double unitPrice,
  required int quantity,
  required double deliveryFee,
  required StationOrderChannel channel,
  required bool pickup,
}) {
  final subtotal = unitPrice * quantity;
  final fee = channel == StationOrderChannel.walkIn || pickup ? 0.0 : deliveryFee;
  return (subtotal: subtotal, fee: fee, total: subtotal + fee);
}

/// Opens the New order form for the owner or staff. Returns true once the
/// order exists.
Future<bool> showStationNewOrderDialog(BuildContext context, {required String stationId}) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _StationNewOrderDialog(stationId: stationId),
  );
  return created == true;
}

class _StationNewOrderDialog extends StatefulWidget {
  const _StationNewOrderDialog({required this.stationId});

  final String stationId;

  @override
  State<_StationNewOrderDialog> createState() => _StationNewOrderDialogState();
}

class _StationNewOrderDialogState extends State<_StationNewOrderDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  StationOrderChannel _channel = StationOrderChannel.phone;
  bool _pickup = true;

  /// The delivery address as the caller says it, for the driver.
  final _address = TextEditingController();
  int _quantity = 1;
  double? _lat;
  double? _lng;
  List<StationProduct> _products = [];
  StationProduct? _product;
  double _deliveryFee = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final products = await ProductService(SupabaseService.instance).fetchStationProducts(widget.stationId);
      final station = await Supabase.instance.client.from('water_stations').select('delivery_fee').eq('id', widget.stationId).single();
      if (!mounted) return;
      setState(() {
        _products = products.where((p) => p.isAvailable).toList();
        _product = _products.isEmpty ? null : _products.first;
        _deliveryFee = (station['delivery_fee'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your products. ${describeError(e)}';
          _loading = false;
        });
      }
    }
  }

  String _productLabel(StationProduct p) =>
      '${describeOrderLine(quantity: 1, waterType: p.waterType, containerCode: p.containerCode, productKind: productKindToString(p.kind))} · ${formatPeso(p.price)}';

  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLatitude: _lat, initialLongitude: _lng, forStation: false)),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = (result['latitude'] as num).toDouble();
        _lng = (result['longitude'] as num).toDouble();
      });
    }
  }

  Future<void> _save() async {
    final product = _product;
    if (product == null) return;
    if (_channel == StationOrderChannel.phone && _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the caller\'s phone number.')));
      return;
    }
    if (_channel == StationOrderChannel.phone && !_pickup && _lat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pin the delivery address on the map.')));
      return;
    }
    final delivering = _channel == StationOrderChannel.phone && !_pickup;
    if (delivering && _address.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Write the delivery address too: house no., street, barangay and a landmark.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      final orderId = await Supabase.instance.client.rpc('station_create_order', params: {
        'p_product_id': product.id,
        'p_quantity': _quantity,
        'p_customer_name': _name.text.trim(),
        'p_phone': _phone.text.trim(),
        'p_channel': _channel == StationOrderChannel.walkIn ? 'walk_in' : 'phone',
        'p_pickup': _channel == StationOrderChannel.walkIn || _pickup,
        'p_lat': _lat,
        'p_lng': _lng,
      });
      if (delivering && orderId is String) {
        try {
          await Supabase.instance.client.rpc('set_order_delivery_address', params: {
            'p_order_id': orderId,
            'p_address': _address.text.trim(),
          });
        } catch (_) {
          // The order is in; the address can be read from the pin.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_channel == StationOrderChannel.walkIn
            ? 'Walk-in sale recorded as delivered and paid.'
            : 'Order added to New orders. Assign a driver when ready.'),
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add the order. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product;
    final totals = product == null
        ? null
        : stationOrderTotal(unitPrice: product.price, quantity: _quantity, deliveryFee: _deliveryFee, channel: _channel, pickup: _pickup);

    return AlertDialog(
      title: const Text('New order'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!)
                : _products.isEmpty
                    ? const Text('List at least one available product under Products first.')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<StationOrderChannel>(
                              segments: const [
                                ButtonSegment(value: StationOrderChannel.phone, icon: Icon(Icons.phone_outlined), label: Text('Phone order')),
                                ButtonSegment(value: StationOrderChannel.walkIn, icon: Icon(Icons.storefront_outlined), label: Text('Walk-in')),
                              ],
                              selected: {_channel},
                              onSelectionChanged: (v) => setState(() => _channel = v.first),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _channel == StationOrderChannel.walkIn
                                  ? 'For a customer at the counter: recorded as handed over and paid now.'
                                  : 'For a customer who called or texted: goes into New orders like an app order.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<StationProduct>(
                              initialValue: product,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Product'),
                              items: [
                                for (final p in _products)
                                  DropdownMenuItem(value: p, child: Text(_productLabel(p), overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (v) => setState(() => _product = v),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text('Quantity', style: theme.textTheme.titleSmall),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'One fewer',
                                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text('$_quantity', style: theme.textTheme.titleLarge),
                                IconButton(
                                  tooltip: 'One more',
                                  onPressed: _quantity < 50 ? () => setState(() => _quantity++) : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            TextField(
                              controller: _name,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: _channel == StationOrderChannel.walkIn ? 'Customer name (optional)' : 'Customer name',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                labelText: _channel == StationOrderChannel.walkIn ? 'Phone (optional)' : 'Phone number',
                              ),
                            ),
                            if (_channel == StationOrderChannel.phone) ...[
                              const SizedBox(height: 12),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: !_pickup,
                                onChanged: (v) => setState(() => _pickup = !v),
                                title: const Text('Deliver to the customer'),
                                subtitle: Text(_pickup ? 'Off: the customer picks up at the station' : 'A driver delivers it'),
                              ),
                              if (!_pickup) ...[
                                OutlinedButton.icon(
                                  onPressed: _pickLocation,
                                  icon: Icon(_lat == null ? Icons.add_location_alt_outlined : Icons.check),
                                  label: Text(_lat == null ? 'Pin the delivery address' : 'Address pinned -- change'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _address,
                                  minLines: 2,
                                  maxLines: 3,
                                  maxLength: 300,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    labelText: 'Delivery address',
                                    hintText: 'House no., street, barangay, landmark',
                                  ),
                                ),
                              ],
                            ],
                            if (totals != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                totals.fee > 0
                                    ? 'Total ${formatPeso(totals.total)} (${formatPeso(totals.subtotal)} + ${formatPeso(totals.fee)} delivery)'
                                    : 'Total ${formatPeso(totals.total)}',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        if (_products.isNotEmpty)
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_channel == StationOrderChannel.walkIn ? 'Record sale' : 'Add order'),
          ),
      ],
    );
  }
}
