import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bulletin.dart';
import '../../services/bulletin_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';
import '../public/bulletin_feed.dart';

/// wasa_admin's Bulletin & Floor Price management screen. Floor prices are
/// a separate read model (`floor_prices`, not a bulletin post) so they keep
/// their own admin-only management section here; the bulletin posts
/// themselves are now handled by the same shared BulletinFeed used
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
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<FloorPrice> _floorPrices = [];
  String? _associationId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final associationId = await _bulletinService.fetchDefaultAssociationId();
    final floorPrices = await _bulletinService.fetchFloorPrices();
    if (mounted) {
      setState(() {
        _associationId = associationId;
        _floorPrices = floorPrices;
        _isLoading = false;
      });
    }
  }

  /// Pass an existing [editing] price to update it in place (water type
  /// locked, since that's the whole row's identity); omit it to set a new
  /// one. Either way this goes through BulletinService.setFloorPrice's
  /// upsert, so there's no way to end up with two rows for the same water
  /// type.
  void _showSetFloorPriceDialog({FloorPrice? editing}) {
    String waterType = editing?.waterType ?? 'purified';
    final priceController = TextEditingController(text: editing?.minPricePerJug.toStringAsFixed(2) ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editing == null ? 'Set Floor Price' : 'Update Floor Price'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: waterType,
                decoration: const InputDecoration(labelText: 'Water Type'),
                items: const [
                  DropdownMenuItem(value: 'purified', child: Text('Purified')),
                  DropdownMenuItem(value: 'mineral', child: Text('Mineral')),
                  DropdownMenuItem(value: 'alkaline', child: Text('Alkaline')),
                ],
                onChanged: editing != null ? null : (v) => setDialogState(() => waterType = v ?? waterType),
              ),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minimum Price per Jug (₱)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final price = double.tryParse(priceController.text.trim());
                if (price == null) return;
                await _bulletinService.setFloorPrice(
                  associationId: _associationId!,
                  waterType: waterType,
                  minPricePerJug: price,
                  setByProfileId: _supabase.auth.currentUser!.id,
                );
                if (context.mounted) Navigator.pop(context);
                _load();
              },
              child: Text(editing == null ? 'Set' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFloorPrice(FloorPrice fp) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Floor Price?',
      message: 'This removes the minimum price enforcement for ${fp.waterType} entirely -- stations will be able to set any price for it again.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bulletin & Floor Prices')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Floor Prices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton.icon(onPressed: () => _showSetFloorPriceDialog(), icon: const Icon(Icons.add), label: const Text('Set Price')),
                    ],
                  ),
                ),
                ..._floorPrices.map((fp) => ListTile(
                      leading: const Icon(Icons.water_drop, color: Colors.blue),
                      title: Text(fp.waterType),
                      subtitle: Text('Effective ${DateFormat('MMM d, yyyy').format(fp.effectiveDate)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(formatPeso(fp.minPricePerJug)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            tooltip: 'Remove',
                            onPressed: () => _deleteFloorPrice(fp),
                          ),
                        ],
                      ),
                      onTap: () => _showSetFloorPriceDialog(editing: fp),
                    )),
                const Divider(height: 24),
                const Expanded(child: BulletinFeed()),
              ],
            ),
    );
  }
}
