import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/my_station.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';

/// The monthly costs an owner enters, by station_cost_profiles column.
const costFields = <String, String>{
  'monthly_rent': 'Rent',
  'monthly_power': 'Electricity',
  'monthly_water_source': 'Source water',
  'monthly_filters_maintenance': 'Filters, UV lamps and maintenance',
  'monthly_wages': 'Wages',
  'monthly_other': 'Other (permits, tests, transport)',
};

/// What one refill costs the station, from its monthly costs and volume:
/// the fixed costs spread over the month's refills, plus the supplies each
/// refill uses (caps, seals, cleaning). Null without a refill count. Pure,
/// so it is unit-tested.
double? costPerRefill({required Map<String, double> monthly, required double suppliesPerRefill, required int refillsPerMonth}) {
  if (refillsPerMonth <= 0) return null;
  final fixed = monthly.values.fold<double>(0, (a, b) => a + b);
  return fixed / refillsPerMonth + suppliesPerRefill;
}

/// The station's own break-even calculator. Its numbers are stored where
/// only this station's owner can read them -- not WASA, not other stations
/// (station_cost_profiles, patch_stations_members.sql). The association
/// does not set or suggest prices; this is for the owner's own planning.
class CostCalculatorScreen extends StatefulWidget {
  const CostCalculatorScreen({super.key});

  @override
  State<CostCalculatorScreen> createState() => _CostCalculatorScreenState();
}

class _CostCalculatorScreenState extends State<CostCalculatorScreen> {
  final _supabase = Supabase.instance.client;
  final _controllers = {for (final k in [...costFields.keys, 'cost_per_refill_supplies', 'refills_per_month']) k: TextEditingController()};
  String? _stationId;
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final station = await fetchMyStation(_supabase);
      if (station == null) {
        setState(() => _isLoading = false);
        return;
      }
      _stationId = station['id'] as String;
      final profile = await _supabase.from('station_cost_profiles').select().eq('station_id', _stationId!).maybeSingle();
      final products = await _supabase
          .from('station_products')
          .select('water_type, container_code, kind, price')
          .eq('station_id', _stationId!)
          .eq('kind', 'refill')
          .order('price');
      if (!mounted) return;
      for (final entry in _controllers.entries) {
        final v = profile?[entry.key];
        entry.value.text = v == null || (v is num && v == 0) ? '' : (v is num && v == v.roundToDouble() ? v.toInt().toString() : '$v');
      }
      setState(() {
        _products = List<Map<String, dynamic>>.from(products);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  double _num(String key) => double.tryParse(_controllers[key]!.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_stationId == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('station_cost_profiles').upsert({
        'station_id': _stationId,
        for (final k in costFields.keys) k: _num(k),
        'cost_per_refill_supplies': _num('cost_per_refill_supplies'),
        'refills_per_month': _num('refills_per_month').round(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Only you can see these numbers.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {String? helper, bool whole = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _controllers[key],
          keyboardType: TextInputType.numberWithOptions(decimal: !whole),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(whole ? r'[0-9]' : r'[0-9.]'))],
          decoration: InputDecoration(labelText: label, helperText: helper, prefixText: whole ? null : '₱ '),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);
    final theme = Theme.of(context);
    final perRefill = costPerRefill(
      monthly: {for (final k in costFields.keys) k: _num(k)},
      suppliesPerRefill: _num('cost_per_refill_supplies'),
      refillsPerMonth: _num('refills_per_month').round(),
    );

    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Your station',
            title: 'Cost calculator',
            subtitle: 'What a refill costs you. Private: WASA and other stations cannot see it.',
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _stationId == null
                        ? const PortalEmptyState(
                            icon: Icons.storefront_outlined,
                            title: 'No station linked',
                            message: 'The calculator works once your account is linked to a station.',
                          )
                        : ListView(
                            padding: density.pagePadding,
                            children: [
                              PortalSection(
                                title: 'Monthly costs',
                                child: Column(children: [for (final e in costFields.entries) _field(e.key, e.value)]),
                              ),
                              SizedBox(height: density.sectionGap),
                              PortalSection(
                                title: 'Per refill',
                                child: Column(
                                  children: [
                                    _field('cost_per_refill_supplies', 'Supplies per refill', helper: 'Caps, seals, cleaning solution'),
                                    _field('refills_per_month', 'Refills sold in a month', whole: true),
                                  ],
                                ),
                              ),
                              SizedBox(height: density.sectionGap),
                              PortalCard(
                                lift: false,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Your cost per refill', style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      perRefill == null ? 'Enter how many refills you sell in a month.' : formatPeso(perRefill),
                                      style: perRefill == null ? theme.textTheme.bodyMedium : theme.textTheme.headlineMedium,
                                    ),
                                    if (perRefill != null && _products.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Text('Against your current prices', style: theme.textTheme.titleSmall),
                                      for (final p in _products)
                                        Builder(builder: (context) {
                                          final price = (p['price'] as num).toDouble();
                                          final margin = price - perRefill;
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              '${p['water_type']} (${p['container_code']}) at ${formatPeso(price)}: '
                                              '${margin >= 0 ? 'you keep ${formatPeso(margin)}' : 'you lose ${formatPeso(-margin)}'} a refill',
                                            ),
                                          );
                                        }),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(height: density.sectionGap),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save my numbers'),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
