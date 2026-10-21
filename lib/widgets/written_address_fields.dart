import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/written_address.dart';

/// The written half of an address, next to the map pin: house no. / street
/// / subdivision, barangay, city and a landmark.
///
/// A pin alone left drivers hunting for the right gate, so stations, saved
/// addresses and orders all ask for this as well. The barangay comes from
/// the association's list, so it matches the directory's barangay filter.
class WrittenAddressFields extends StatefulWidget {
  const WrittenAddressFields({
    super.key,
    required this.street,
    required this.city,
    required this.landmark,
    required this.barangay,
    required this.onBarangayChanged,
    this.enabled = true,
  });

  final TextEditingController street;
  final TextEditingController city;
  final TextEditingController landmark;
  final String? barangay;
  final ValueChanged<String?> onBarangayChanged;
  final bool enabled;

  @override
  State<WrittenAddressFields> createState() => _WrittenAddressFieldsState();
}

class _WrittenAddressFieldsState extends State<WrittenAddressFields> {
  static List<String>? _cache;
  List<String> _barangays = _cache ?? const [];

  @override
  void initState() {
    super.initState();
    if (widget.city.text.trim().isEmpty) widget.city.text = kDefaultCity;
    if (_cache == null) _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client.from('barangays').select('name').order('name');
      _cache = [for (final r in rows) r['name'] as String];
      if (mounted) setState(() => _barangays = _cache!);
    } catch (_) {
      // Offline: the list fills in next time; the rest of the form works.
    }
  }

  @override
  Widget build(BuildContext context) {
    // A saved value that isn't in the list (typed before the list existed)
    // stays selectable rather than being silently dropped.
    final options = {
      ..._barangays,
      if (widget.barangay != null && widget.barangay!.isNotEmpty) widget.barangay!,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.street,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'House no., street, subdivision',
            hintText: 'e.g. Blk 3 Lot 5, Sampaguita St., Greenwoods',
            prefixIcon: Icon(Icons.home_outlined),
          ),
          validator: (v) => (v ?? '').trim().length < 3 ? 'Enter the house no., street or subdivision' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          // Rebuilt when the value changes from outside (a saved address
          // picked on the order form): the field reads initialValue once.
          key: ValueKey(widget.barangay),
          isExpanded: true,
          initialValue: options.contains(widget.barangay) ? widget.barangay : null,
          decoration: InputDecoration(
            labelText: 'Barangay',
            prefixIcon: const Icon(Icons.location_city_outlined),
            helperText: _barangays.isEmpty ? 'Loading the list...' : null,
          ),
          items: [for (final b in options) DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))],
          onChanged: widget.enabled ? widget.onBarangayChanged : null,
          validator: (v) => (v ?? '').isEmpty ? 'Choose the barangay' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.city,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.map_outlined)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the city' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.landmark,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Landmark (optional)',
            hintText: 'e.g. beside the chapel, blue gate',
            prefixIcon: Icon(Icons.flag_outlined),
          ),
        ),
      ],
    );
  }
}
