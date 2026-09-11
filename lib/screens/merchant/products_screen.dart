import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bulletin.dart';
import '../../models/product.dart';
import '../../services/bulletin_service.dart';
import '../../services/product_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';

/// Checks a price an owner typed. Returns what's wrong, or null when valid.
/// The server enforces the same floor; checking here just means the owner
/// hears about it before pressing Save rather than after.
String? validateProductPrice(String input, {double? floor}) {
  final price = double.tryParse(input.trim());
  if (price == null) return 'Enter a price, e.g. 25';
  if (price <= 0) return 'The price must be more than ₱0';
  if (floor != null && price < floor) return 'The association minimum is ${formatPeso(floor)}';
  return null;
}

String? validateDeliveryFee(String input) {
  final fee = double.tryParse(input.trim());
  if (fee == null) return 'Enter an amount, e.g. 15 -- or 0 for free delivery';
  if (fee < 0) return "The delivery fee can't be negative";
  return null;
}

/// Whether [products] already lists this water type, container and kind
/// (ignoring [exceptId], the product being edited). The database rejects a
/// duplicate too; this lets the dialog say so in plain words.
bool isDuplicateProduct(
  List<StationProduct> products, {
  required String waterType,
  required String containerCode,
  required ProductKind kind,
  String? exceptId,
}) {
  return products.any((p) =>
      p.id != exceptId && p.waterType == waterType && p.containerCode == containerCode && p.kind == kind);
}

String productTitle(StationProduct product, ContainerType? container) {
  final label = container?.label ?? product.containerCode;
  return product.kind == ProductKind.refill ? '$label refill' : '$label (new container)';
}

/// What a station sells and at what price -- the station owner's catalog.
///
/// This replaces a single price per station that owners had no way to set at
/// all (registration never asked for one and it defaulted to ₱0), and the
/// water-type and container chips that were buried under Profile > Station
/// Info. A station can't take orders until it lists at least one product.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _supabase = Supabase.instance.client;
  final _productService = ProductService(SupabaseService.instance);
  final _bulletinService = BulletinService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  String? _stationId;
  double _deliveryFee = 0;
  List<StationProduct> _products = [];
  List<ContainerType> _containers = [];
  List<FloorPrice> _floors = [];

  Map<String, ContainerType> get _containerByCode => {for (final c in _containers) c.code: c};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser!.id;
      final station = await _supabase
          .from('water_stations')
          .select('id, delivery_fee')
          .eq('owner_profile_id', userId)
          .maybeSingle();
      if (station == null) {
        if (mounted) {
          setState(() {
            _error = 'No station is linked to this account.';
            _isLoading = false;
          });
        }
        return;
      }
      final stationId = station['id'] as String;
      final products = await _productService.fetchStationProducts(stationId);
      // Retired containers included, so a product the owner already sells in
      // one still shows its proper name.
      final containers = await _productService.fetchContainerTypes(includeInactive: true);
      final floors = await _bulletinService.fetchFloorPrices();
      if (mounted) {
        setState(() {
          _stationId = stationId;
          _deliveryFee = (station['delivery_fee'] as num).toDouble();
          _products = products;
          _containers = containers;
          _floors = floors;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your products: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _editProduct({StationProduct? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductEditorDialog(
        stationId: _stationId!,
        existing: existing,
        products: _products,
        containers: _containers.where((c) => c.isActive || c.code == existing?.containerCode).toList(),
        floors: _floors,
        productService: _productService,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _editDeliveryFee() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DeliveryFeeDialog(
        stationId: _stationId!,
        currentFee: _deliveryFee,
        productService: _productService,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _setAvailability(StationProduct product, bool isAvailable) async {
    try {
      await _productService.setAvailability(product.id, isAvailable);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _delete(StationProduct product) async {
    final title = productTitle(product, _containerByCode[product.containerCode]);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove this product?',
      message: 'Customers will no longer be able to order ${waterTypeLabel(product.waterType)} $title. '
          'Past orders keep what was bought and the price paid.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await _productService.deleteProduct(product.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products & Prices')),
      floatingActionButton: _stationId == null || _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editProduct(),
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                // Bottom padding keeps the last row clear of the FAB.
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _buildDeliveryFeeCard(),
                  const SizedBox(height: 20),
                  if (_products.isEmpty) _buildEmptyState() else ..._buildProductSections(),
                ],
              ),
            ),
    );
  }

  Widget _buildDeliveryFeeCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.delivery_dining_outlined),
        title: const Text('Delivery fee'),
        subtitle: Text(_deliveryFee == 0 ? 'Free delivery' : '${formatPeso(_deliveryFee)} per order'),
        trailing: TextButton(onPressed: _editDeliveryFee, child: const Text('Edit')),
        onTap: _editDeliveryFee,
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text("Customers can't order from you yet", style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'List at least one product with its price -- for example, a Purified Slim 5-gal refill. '
              'Your station becomes orderable as soon as you do.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _editProduct(),
              icon: const Icon(Icons.add),
              label: const Text('Add your first product'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildProductSections() {
    final theme = Theme.of(context);
    final grouped = groupProductsByWaterType(_products, _containerByCode);
    return [
      for (final entry in grouped.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(waterTypeLabel(entry.key), style: theme.textTheme.titleLarge),
        ),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildProductTile(entry.value[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _buildProductTile(StationProduct product) {
    final container = _containerByCode[product.containerCode];
    final notes = <String>[
      if (!product.isAvailable) 'hidden from customers',
      if (container != null && !container.isActive) 'container retired by the association',
    ];
    return ListTile(
      title: Text(productTitle(product, container)),
      subtitle: Text([formatPeso(product.price), ...notes].join(' · ')),
      onTap: () => _editProduct(existing: product),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: product.isAvailable ? 'Available -- tap to hide from customers' : 'Hidden -- tap to make available',
            child: Switch(
              value: product.isAvailable,
              onChanged: (value) => _setAvailability(product, value),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove product',
            onPressed: () => _delete(product),
          ),
        ],
      ),
    );
  }
}

/// Add/edit dialog. A StatefulWidget of its own so the price controller is
/// disposed with the dialog -- disposing it when showDialog's future
/// completes would be too early, since the dialog is still on screen during
/// its closing animation.
class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.stationId,
    required this.existing,
    required this.products,
    required this.containers,
    required this.floors,
    required this.productService,
  });

  final String stationId;
  final StationProduct? existing;
  final List<StationProduct> products;
  final List<ContainerType> containers;
  final List<FloorPrice> floors;
  final ProductService productService;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late String _waterType = widget.existing?.waterType ?? kWaterTypes.first;
  late String? _containerCode =
      widget.existing?.containerCode ?? (widget.containers.isEmpty ? null : widget.containers.first.code);
  late ProductKind _kind = widget.existing?.kind ?? ProductKind.refill;
  late bool _isAvailable = widget.existing?.isAvailable ?? true;
  late final _priceController = TextEditingController(text: widget.existing?.price.toStringAsFixed(2) ?? '');
  String? _priceError;
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  double? get _floor => _kind == ProductKind.refill && _containerCode != null
      ? floorPriceFor(widget.floors, _waterType, _containerCode!)
      : null;

  Future<void> _save() async {
    final containerCode = _containerCode;
    if (containerCode == null) return;
    final priceError = validateProductPrice(_priceController.text, floor: _floor);
    final duplicate = isDuplicateProduct(
      widget.products,
      waterType: _waterType,
      containerCode: containerCode,
      kind: _kind,
      exceptId: widget.existing?.id,
    );
    setState(() {
      _priceError = priceError;
      _formError = duplicate ? 'You already list this product -- edit that one instead.' : null;
    });
    if (priceError != null || duplicate) return;

    setState(() => _saving = true);
    try {
      await widget.productService.saveProduct(
        id: widget.existing?.id,
        stationId: widget.stationId,
        waterType: _waterType,
        containerCode: containerCode,
        kind: _kind,
        price: double.parse(_priceController.text.trim()),
        isAvailable: _isAvailable,
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      // The floor-price and uniqueness messages come from the database and
      // are written for owners, so they're shown as-is.
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final floor = _floor;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add product' : 'Edit product'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _waterType,
              decoration: const InputDecoration(labelText: 'Water type'),
              items: [
                for (final w in kWaterTypes) DropdownMenuItem(value: w, child: Text(waterTypeLabel(w))),
              ],
              onChanged: _saving ? null : (v) => setState(() => _waterType = v ?? _waterType),
            ),
            if (_waterType == 'alkaline')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Selling alkaline requires two extra permits before you're accredited for it.",
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _containerCode,
              decoration: const InputDecoration(labelText: 'Container'),
              items: [
                for (final c in widget.containers) DropdownMenuItem(value: c.code, child: Text(c.label)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _containerCode = v),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ProductKind>(
              segments: const [
                ButtonSegment(value: ProductKind.refill, label: Text('Refill'), icon: Icon(Icons.autorenew)),
                ButtonSegment(value: ProductKind.newContainer, label: Text('New container'), icon: Icon(Icons.add_box_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: _saving ? null : (s) => setState(() => _kind = s.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _kind == ProductKind.refill
                    ? 'The customer brings or exchanges an empty container.'
                    : 'The customer buys the container along with the water.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '₱ ',
                errorText: _priceError,
                helperText: floor != null ? 'Association minimum: ${formatPeso(floor)}' : null,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isAvailable,
              onChanged: _saving ? null : (v) => setState(() => _isAvailable = v),
              title: const Text('Available to customers'),
            ),
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_formError!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving || _containerCode == null ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }
}

class _DeliveryFeeDialog extends StatefulWidget {
  const _DeliveryFeeDialog({required this.stationId, required this.currentFee, required this.productService});

  final String stationId;
  final double currentFee;
  final ProductService productService;

  @override
  State<_DeliveryFeeDialog> createState() => _DeliveryFeeDialogState();
}

class _DeliveryFeeDialogState extends State<_DeliveryFeeDialog> {
  late final _controller = TextEditingController(text: widget.currentFee.toStringAsFixed(2));
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = validateDeliveryFee(_controller.text);
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _saving = true);
    try {
      await widget.productService.updateDeliveryFee(widget.stationId, double.parse(_controller.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delivery fee'),
      content: TextField(
        controller: _controller,
        enabled: !_saving,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Fee per order',
          prefixText: '₱ ',
          helperText: 'Enter 0 for free delivery',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }
}
