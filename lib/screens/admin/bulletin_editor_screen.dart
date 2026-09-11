import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bulletin.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../services/bulletin_service.dart';
import '../../services/product_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../public/bulletin_feed.dart';

/// Validates a container code typed by the admin: lower-case letters,
/// digits and underscores, like the seeded `slim_5gal`. Codes are stored on
/// orders and products, so they can't be renamed once created -- only the
/// label can.
String? validateContainerCode(String? input) {
  final code = input?.trim() ?? '';
  if (code.isEmpty) return 'Enter a code';
  if (!RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(code)) return 'Use 2-40 lower-case letters, digits or _';
  return null;
}

/// wasa_admin's Bulletin, Floor Price and Container management screen.
/// Floor prices and the container list are read models of their own
/// (`floor_prices`, `container_types`), managed in their own tabs; the
/// bulletin posts are handled by the same shared BulletinFeed used
/// everywhere else (screens/public/bulletin_feed.dart) -- wasa_admin gets
/// all 4 categories unlocked in its "+ New Post" sheet automatically, since
/// BulletinFeed derives the allowed categories from the signed-in user's
/// role via Riverpod rather than needing a special admin-only dialog here.
class BulletinEditorScreen extends StatefulWidget {
  const BulletinEditorScreen({super.key});

  @override
  State<BulletinEditorScreen> createState() => _BulletinEditorScreenState();
}

class _BulletinEditorScreenState extends State<BulletinEditorScreen> {
  final _bulletinService = BulletinService(SupabaseService.instance);
  final _productService = ProductService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;
  List<FloorPrice> _floorPrices = [];
  List<ContainerType> _containers = [];
  String? _associationId;

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
      final associationId = await _bulletinService.fetchDefaultAssociationId();
      final floorPrices = await _bulletinService.fetchFloorPrices();
      final containers = await _productService.fetchContainerTypes(includeInactive: true);
      if (mounted) {
        setState(() {
          _associationId = associationId;
          _floorPrices = floorPrices;
          _containers = containers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load floor prices: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _containerName(String? code) {
    if (code == null) return 'Any container';
    for (final c in _containers) {
      if (c.code == code) return c.label;
    }
    return containerLabel(code) ?? code;
  }

  String _floorTitle(FloorPrice fp) => '${waterTypeLabel(fp.waterType)} · ${_containerName(fp.containerCode)} refill';

  /// Pass an existing [editing] floor to update it in place (water type and
  /// container locked, since together they're the row's identity); omit it
  /// to set a new one. Either way this goes through
  /// BulletinService.setFloorPrice's upsert, so there's no way to end up
  /// with two rows for the same water type and container.
  Future<void> _showSetFloorPriceDialog({FloorPrice? editing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FloorPriceDialog(
        editing: editing,
        containers: _containers.where((c) => c.isActive || c.code == editing?.containerCode).toList(),
        onSave: (waterType, containerCode, price) => _bulletinService.setFloorPrice(
          associationId: _associationId!,
          waterType: waterType,
          containerCode: containerCode,
          minPricePerJug: price,
          setByProfileId: _supabase.auth.currentUser!.id,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteFloorPrice(FloorPrice fp) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Floor Price?',
      message: 'Stations will be able to set any price for ${_floorTitle(fp).toLowerCase()}s again.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;

    try {
      await _bulletinService.deleteFloorPrice(fp.id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showContainerDialog({ContainerType? editing}) async {
    final nextSortOrder = _containers.isEmpty ? 10 : _containers.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 10;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ContainerDialog(
        editing: editing,
        existingCodes: {for (final c in _containers) c.code},
        defaultSortOrder: nextSortOrder,
        onSave: _productService.saveContainerType,
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const AdminPageHeader(title: 'Bulletin & Prices'),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Floor prices'),
              Tab(text: 'Containers'),
              Tab(text: 'Bulletin posts'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : TabBarView(
                    children: [
                      _buildFloorPrices(),
                      _buildContainers(),
                      const BulletinFeed(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionIntro(String text, {required String actionLabel, required VoidCallback onAction}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton.tonalIcon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _buildFloorPrices() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _sectionIntro(
            'The lowest price a station may charge for a refill of one water type in one container. '
            'New-container sales are not covered, since their price includes the container.',
            actionLabel: 'Set floor price',
            onAction: () => _showSetFloorPriceDialog(),
          ),
          if (_floorPrices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text('No floor prices set yet.', style: TextStyle(color: Colors.grey.shade600)),
            ),
          ..._floorPrices.map((fp) => ListTile(
                leading: const Icon(Icons.water_drop, color: Colors.blue),
                title: Text(_floorTitle(fp)),
                subtitle: Text('Effective ${DateFormat('MMM d, yyyy').format(fp.effectiveDate)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Min ${formatPeso(fp.minPricePerJug)}'),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      tooltip: 'Remove',
                      onPressed: () => _deleteFloorPrice(fp),
                    ),
                  ],
                ),
                onTap: fp.containerCode == null ? null : () => _showSetFloorPriceDialog(editing: fp),
              )),
        ],
      ),
    );
  }

  Widget _buildContainers() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          _sectionIntro(
            'The containers stations can list products in. Retiring one hides it from new products '
            'and from customers; past orders keep it.',
            actionLabel: 'Add container',
            onAction: () => _showContainerDialog(),
          ),
          ..._containers.map((c) {
            final details = [
              '${NumberFormat.decimalPattern().format(c.volumeMl)} mL',
              c.isReturnable ? 'returnable' : 'not returnable',
              if (c.ledgerJugType != null) 'tracked by the jug clearinghouse',
            ].join(' · ');
            return ListTile(
              leading: Icon(c.isReturnable ? Icons.autorenew : Icons.local_drink_outlined, color: c.isActive ? Colors.blue : Colors.grey),
              title: Text(c.label, style: TextStyle(color: c.isActive ? null : Colors.grey)),
              subtitle: Text(c.isActive ? details : 'Retired · $details'),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => _showContainerDialog(editing: c),
            );
          }),
        ],
      ),
    );
  }
}

/// Owns its controller (a dialog is still on screen during its exit
/// animation, so disposing when showDialog's future completes is too early).
class _FloorPriceDialog extends StatefulWidget {
  const _FloorPriceDialog({required this.editing, required this.containers, required this.onSave});

  final FloorPrice? editing;
  final List<ContainerType> containers;
  final Future<void> Function(String waterType, String containerCode, double price) onSave;

  @override
  State<_FloorPriceDialog> createState() => _FloorPriceDialogState();
}

class _FloorPriceDialogState extends State<_FloorPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _priceController = TextEditingController(text: widget.editing?.minPricePerJug.toStringAsFixed(2) ?? '');
  late String _waterType = widget.editing?.waterType ?? kWaterTypes.first;
  late String? _containerCode = widget.editing?.containerCode ?? (widget.containers.isEmpty ? null : widget.containers.first.code);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _containerCode == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_waterType, _containerCode!, double.parse(_priceController.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not set floor price: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.editing != null;
    return AlertDialog(
      title: Text(locked ? 'Update Floor Price' : 'Set Floor Price'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _waterType,
                decoration: const InputDecoration(labelText: 'Water type'),
                items: [for (final w in kWaterTypes) DropdownMenuItem(value: w, child: Text(waterTypeLabel(w)))],
                onChanged: locked ? null : (v) => setState(() => _waterType = v ?? _waterType),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _containerCode,
                decoration: const InputDecoration(labelText: 'Container'),
                items: [for (final c in widget.containers) DropdownMenuItem(value: c.code, child: Text(c.label))],
                onChanged: locked ? null : (v) => setState(() => _containerCode = v),
                validator: (v) => v == null ? 'Choose a container' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Minimum refill price (₱)'),
                validator: (v) {
                  final price = double.tryParse(v?.trim() ?? '');
                  if (price == null || price <= 0) return 'Enter a price above ₱0';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(locked ? 'Update' : 'Set'),
        ),
      ],
    );
  }
}

class _ContainerDialog extends StatefulWidget {
  const _ContainerDialog({
    required this.editing,
    required this.existingCodes,
    required this.defaultSortOrder,
    required this.onSave,
  });

  final ContainerType? editing;
  final Set<String> existingCodes;
  final int defaultSortOrder;
  final Future<void> Function({
    required String code,
    required String label,
    required int volumeMl,
    required bool isReturnable,
    required int sortOrder,
    required bool isActive,
  }) onSave;

  @override
  State<_ContainerDialog> createState() => _ContainerDialogState();
}

class _ContainerDialogState extends State<_ContainerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _codeController = TextEditingController(text: widget.editing?.code ?? '');
  late final _labelController = TextEditingController(text: widget.editing?.label ?? '');
  late final _volumeController = TextEditingController(text: widget.editing?.volumeMl.toString() ?? '');
  late final _sortController = TextEditingController(text: (widget.editing?.sortOrder ?? widget.defaultSortOrder).toString());
  late bool _isReturnable = widget.editing?.isReturnable ?? false;
  late bool _isActive = widget.editing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _labelController.dispose();
    _volumeController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        code: _codeController.text.trim(),
        label: _labelController.text.trim(),
        volumeMl: int.parse(_volumeController.text.trim()),
        isReturnable: _isReturnable,
        sortOrder: int.parse(_sortController.text.trim()),
        isActive: _isActive,
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the container: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.editing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add Container' : 'Edit ${widget.editing!.label}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Name shown to customers', hintText: 'e.g. 1-liter bottle'),
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codeController,
                enabled: isNew,
                decoration: InputDecoration(
                  labelText: 'Code',
                  hintText: 'e.g. bottle_1l',
                  helperText: isNew ? "Can't be changed later" : null,
                ),
                validator: (v) {
                  if (!isNew) return null;
                  final error = validateContainerCode(v);
                  if (error != null) return error;
                  if (widget.existingCodes.contains(v!.trim())) return 'That code is already used';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _volumeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Volume (mL)'),
                validator: (v) {
                  final ml = int.tryParse(v?.trim() ?? '');
                  return ml == null || ml <= 0 ? 'Enter the volume in mL' : null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _sortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Display order', helperText: 'Lower numbers are listed first'),
                validator: (v) => int.tryParse(v?.trim() ?? '') == null ? 'Enter a whole number' : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Returnable'),
                subtitle: const Text('Customers hand back an empty on refills'),
                value: _isReturnable,
                onChanged: (v) => setState(() => _isReturnable = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offered'),
                subtitle: const Text('Off retires it: hidden from new products and customers'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(isNew ? 'Add' : 'Save')),
      ],
    );
  }
}
