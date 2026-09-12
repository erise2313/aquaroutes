import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/customer_address.dart';
import '../../services/address_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_map_tiles.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../app_route.dart';
import '../../utils/error_text.dart';

/// A customer's saved delivery addresses. Ordering used to mean dropping a
/// pin on the map every single time, even for the same house every week.
class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  final _service = AddressService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<CustomerAddress> _addresses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final addresses = await _service.fetchAddresses();
      if (mounted) {
        setState(() {
          _addresses = addresses;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your addresses. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _edit({CustomerAddress? existing}) async {
    final saved = await Navigator.push<bool>(
      context,
      appRoute(AddressEditorScreen(existing: existing, isFirst: _addresses.isEmpty)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(CustomerAddress address) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove ${address.label}?',
      message: 'Orders already placed keep the address they were delivered to.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await _service.deleteAddress(address.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove it. ${describeError(e)}')));
    }
  }

  Future<void> _makeDefault(CustomerAddress address) async {
    try {
      await _service.setDefault(address.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update it. ${describeError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add address'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _addresses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.home_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text('No saved addresses yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      'Save the places you order to -- home, work -- and the order form fills them in for you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: _addresses.length,
                itemBuilder: (context, index) {
                  final address = _addresses[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(address.isDefault ? Icons.home : Icons.place_outlined),
                      title: Row(
                        children: [
                          Flexible(child: Text(address.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                          if (address.isDefault) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text('Default', style: TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        address.notes ??
                            '${address.latitude.toStringAsFixed(4)}, ${address.longitude.toStringAsFixed(4)}',
                      ),
                      onTap: () => _edit(existing: address),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'default') _makeDefault(address);
                          if (value == 'edit') _edit(existing: address);
                          if (value == 'delete') _delete(address);
                        },
                        itemBuilder: (_) => [
                          if (!address.isDefault)
                            const PopupMenuItem(value: 'default', child: Text('Make default')),
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Remove')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Map + label for one address. Pops `true` once saved.
class AddressEditorScreen extends StatefulWidget {
  const AddressEditorScreen({super.key, this.existing, this.isFirst = false, this.initialPoint});

  final CustomerAddress? existing;

  /// The first address someone saves becomes their default automatically.
  final bool isFirst;

  /// Used when saving a pin dropped on the order form.
  final LatLng? initialPoint;

  @override
  State<AddressEditorScreen> createState() => _AddressEditorScreenState();
}

class _AddressEditorScreenState extends State<AddressEditorScreen> {
  final _service = AddressService(SupabaseService.instance);
  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  late final _labelController = TextEditingController(text: widget.existing?.label ?? '');
  late final _notesController = TextEditingController(text: widget.existing?.notes ?? '');
  late LatLng _point = widget.existing != null
      ? LatLng(widget.existing!.latitude, widget.existing!.longitude)
      : (widget.initialPoint ?? const LatLng(14.3868, 120.8817));
  late bool _isDefault = widget.existing?.isDefault ?? widget.isFirst;
  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await _service.saveAddress(
        id: widget.existing?.id,
        label: _labelController.text,
        latitude: _point.latitude,
        longitude: _point.longitude,
        notes: _notesController.text,
        isDefault: _isDefault,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save the address. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add address' : 'Edit ${widget.existing!.label}')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _point,
                    initialZoom: 16,
                    onTap: (_, point) => setState(() => _point = point),
                  ),
                  children: [
                    const AppMapTiles(),
                    MarkerLayer(markers: [
                      Marker(point: _point, width: 40, height: 40, child: const MapPin(kind: MapPinKind.deliveryAddress)),
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
                    child: const Text('Tap the map to move the pin', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _labelController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name', hintText: 'Home, Work, Mama\'s house', border: OutlineInputBorder()),
                      validator: validateAddressLabel,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _notesController,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Landmark or instructions (optional)',
                        hintText: 'Blue gate beside the sari-sari store',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _isDefault,
                      onChanged: (v) => setState(() => _isDefault = v),
                      title: const Text('Use as my default address'),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(_saving ? 'Saving…' : 'Save address'),
                      ),
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
