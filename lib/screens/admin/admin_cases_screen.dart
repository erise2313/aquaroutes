import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_palette.dart';
import '../../constants/brand_tokens.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/officer_can.dart';
import '../../widgets/portal/portal.dart';

/// What each case kind is about. Never price: the association governs
/// safety and conduct, not what a station charges (Rollout plan, ground
/// rule).
const caseKindLabels = {
  'permit': 'Permit',
  'water_test': 'Water test',
  'conduct': 'Conduct',
  'complaint': 'Customer complaint',
};

const caseStatusLabels = {
  'open': 'Open',
  'warning_issued': 'Warning issued',
  'board_action': 'Referred to the board',
  'resolved': 'Resolved',
};

Color caseStatusColor(String? status) => switch (status) {
      'resolved' => BrandStatus.success,
      'board_action' => BrandStatus.danger,
      'warning_issued' => BrandStatus.warning,
      _ => BrandStatus.info,
    };

/// Compliance cases: one written record per issue with a station -- what
/// it was, the evidence, the decision, which officer made it and when, and
/// the station's own written response. Every change is in the audit log;
/// an officer linked to the station can't handle its case
/// (supabase/patch_compliance.sql).
class AdminCasesScreen extends StatefulWidget {
  const AdminCasesScreen({super.key});

  @override
  State<AdminCasesScreen> createState() => _AdminCasesScreenState();
}

class _AdminCasesScreenState extends State<AdminCasesScreen> {
  final _supabase = Supabase.instance.client;
  final _search = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _cases = [];
  Map<String, String> _stations = {};
  String _query = '';
  String? _status = 'open_any';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final cases = await _supabase.from('compliance_cases').select().order('created_at', ascending: false);
      final stations = await _supabase.from('water_stations').select('id, station_name').order('station_name');
      if (!mounted) return;
      setState(() {
        _cases = List<Map<String, dynamic>>.from(cases);
        _stations = {for (final s in stations) s['id'] as String: (s['station_name'] as String?) ?? 'Station'};
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load cases. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _cases.where((c) {
      if (_status == 'open_any' && c['status'] == 'resolved') return false;
      if (_status != null && _status != 'open_any' && c['status'] != _status) return false;
      if (q.isEmpty) return true;
      return [(_stations[c['station_id']] ?? ''), c['summary'] ?? '', c['evidence'] ?? '']
          .any((f) => (f as String).toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CaseDialog(stations: _stations, existing: existing),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Column(
      children: [
        AdminPageHeader(
          eyebrow: 'Compliance',
          title: 'Compliance cases',
          subtitle: 'A written record of each issue with a station, its decision and the station\'s response',
          actions: [
            OfficerCan(area: OfficerArea.stations, child: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Open a case'))),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : Column(
                      children: [
                        AdminFilterBar(
                          searchHint: 'Search by station or what happened',
                          searchController: _search,
                          onSearchChanged: (v) => setState(() => _query = v),
                          filters: [
                            AdminFilterGroup(
                              label: 'Status',
                              options: {'open_any': 'Not resolved', null: 'All', ...caseStatusLabels},
                              selected: _status,
                              onChanged: (v) => setState(() => _status = v),
                            ),
                          ],
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? const PortalEmptyState(
                                  icon: Icons.gavel_outlined,
                                  title: 'No cases here',
                                  message: 'Open a case when a station has a permit, water-test, conduct or complaint issue to follow up in writing.',
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                    children: [for (final c in visible) _buildTile(c)],
                                  ),
                                ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> c) {
    final palette = AdminPalette.of(context);
    final fmt = DateFormat('MMM d, yyyy');
    return PortalCard(
      margin: const EdgeInsets.only(bottom: 10),
      accent: caseStatusColor(c['status'] as String?),
      onTap: () => _edit(existing: c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_stations[c['station_id']] ?? 'Station', style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink)),
              StatusPill(label: caseStatusLabels[c['status']] ?? '', color: caseStatusColor(c['status'] as String?)),
            ],
          ),
          Text(
            '${caseKindLabels[c['kind']] ?? ''} · opened ${fmt.format(DateTime.parse(c['created_at'] as String).toLocal())}',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(c['summary'] as String, style: TextStyle(color: palette.ink)),
          if (c['station_response'] != null) ...[
            const SizedBox(height: 6),
            Text('Station\'s response: ${c['station_response']}', style: TextStyle(color: palette.inkMuted, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

class _CaseDialog extends StatefulWidget {
  const _CaseDialog({required this.stations, this.existing});

  final Map<String, String> stations;
  final Map<String, dynamic>? existing;

  @override
  State<_CaseDialog> createState() => _CaseDialogState();
}

class _CaseDialogState extends State<_CaseDialog> {
  late String? _stationId = widget.existing?['station_id'] as String?;
  late String _kind = widget.existing?['kind'] as String? ?? 'permit';
  late String _status = widget.existing?['status'] as String? ?? 'open';
  late final _summary = TextEditingController(text: widget.existing?['summary'] as String?);
  late final _evidence = TextEditingController(text: widget.existing?['evidence'] as String?);
  late final _decision = TextEditingController(text: widget.existing?['decision'] as String?);
  bool _saving = false;

  Future<void> _save() async {
    if (_stationId == null || _summary.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose the station and say what the issue is.')));
      return;
    }
    if (_status != 'open' && _decision.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write the decision and its reason.')));
      return;
    }
    setState(() => _saving = true);
    final data = {
      'station_id': _stationId,
      'kind': _kind,
      'summary': _summary.text.trim(),
      'evidence': _evidence.text.trim().isEmpty ? null : _evidence.text.trim(),
      'status': _status,
      'decision': _decision.text.trim().isEmpty ? null : _decision.text.trim(),
    };
    try {
      final client = Supabase.instance.client;
      if (widget.existing == null) {
        await client.from('compliance_cases').insert(data);
      } else {
        await client.from('compliance_cases').update(data).eq('id', widget.existing!['id'] as String);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final sorted = widget.stations.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
      title: Text(existing == null ? 'Open a compliance case' : 'Compliance case'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _stationId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Station'),
                items: [for (final s in sorted) DropdownMenuItem(value: s.key, child: Text(s.value, overflow: TextOverflow.ellipsis))],
                onChanged: existing == null ? (v) => setState(() => _stationId = v) : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'About'),
                items: [for (final k in caseKindLabels.entries) DropdownMenuItem(value: k.key, child: Text(k.value))],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              const SizedBox(height: 12),
              TextField(controller: _summary, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'What happened')),
              const SizedBox(height: 12),
              TextField(controller: _evidence, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Evidence (documents, dates, reports)')),
              if (existing?['station_response'] != null) ...[
                const SizedBox(height: 12),
                Text('Station\'s response', style: Theme.of(context).textTheme.labelLarge),
                Text(existing!['station_response'] as String),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final s in caseStatusLabels.entries) DropdownMenuItem(value: s.key, child: Text(s.value))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextField(controller: _decision, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Decision and reason')),
              const SizedBox(height: 8),
              Text(
                'The station is notified when the case opens and when its status changes, and can answer in writing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(existing == null ? 'Open case' : 'Save')),
      ],
    );
  }
}
