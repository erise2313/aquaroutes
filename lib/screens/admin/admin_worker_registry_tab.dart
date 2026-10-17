import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../utils/error_text.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';

/// Every worker across all member stations, with their clearance -- the
/// association-wide registry an officer is responsible for.
///
/// The Workers section used to show only the review queues, so an officer
/// could not answer "who is flagged right now?" or look up one driver's
/// record without waiting for something about them to land in a queue.
class AdminWorkerRegistryTab extends StatefulWidget {
  const AdminWorkerRegistryTab({super.key});

  @override
  State<AdminWorkerRegistryTab> createState() => _AdminWorkerRegistryTabState();
}

class _AdminWorkerRegistryTabState extends State<AdminWorkerRegistryTab> {
  final _supabase = Supabase.instance.client;
  final _search = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _workers = [];
  String _query = '';
  String? _clearance;

  static const _clearanceLabels = {
    'pending_clearance': 'Pending clearance',
    'cleared': 'Cleared',
    'flagged': 'Flagged',
  };

  static Color _colorFor(String? c) => switch (c) {
        'cleared' => AppColors.cleared,
        'flagged' => AppColors.flagged,
        _ => AppColors.pendingClearance,
      };

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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('workers')
          .select('id, full_name, worker_code, clearance_status, vehicle_plate, water_stations(station_name)')
          .order('full_name');
      if (mounted) {
        setState(() {
          _workers = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load workers. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final q = _query.trim().toLowerCase();
    return _workers.where((w) {
      if (_clearance != null && w['clearance_status'] != _clearance) return false;
      if (q.isEmpty) return true;
      final name = (w['full_name'] as String? ?? '').toLowerCase();
      final code = (w['worker_code'] as String? ?? '').toLowerCase();
      final station = ((w['water_stations'] as Map?)?['station_name'] as String? ?? '').toLowerCase();
      return name.contains(q) || code.contains(q) || station.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 5));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final theme = Theme.of(context);
    final visible = _visible;
    final counts = {for (final k in _clearanceLabels.keys) k: _workers.where((w) => w['clearance_status'] == k).length};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search by name, worker code or station',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text('All (${_workers.length})'),
                selected: _clearance == null,
                onSelected: (_) => setState(() => _clearance = null),
              ),
              for (final e in _clearanceLabels.entries)
                ChoiceChip(
                  label: Text('${e.value} (${counts[e.key]})'),
                  selected: _clearance == e.key,
                  onSelected: (_) => setState(() => _clearance = _clearance == e.key ? null : e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            PortalEmptyState(
              icon: Icons.badge_outlined,
              title: _workers.isEmpty ? 'No workers registered yet' : 'No worker matches',
              message: _workers.isEmpty
                  ? 'Drivers appear here once they register with a station\'s invite code.'
                  : 'Try a different name or clear the filter.',
            )
          else
            for (final w in visible)
              PortalCard(
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => showWorkerRecord(context, w),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w['full_name'] as String? ?? 'Unnamed', style: theme.textTheme.titleMedium),
                          Text(
                            '${w['worker_code'] ?? ''} · ${(w['water_stations'] as Map?)?['station_name'] ?? 'No station'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: _clearanceLabels[w['clearance_status']] ?? 'Unknown',
                      color: _colorFor(w['clearance_status'] as String?),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// One worker's full record for an officer: clearance, credentials, every
/// incident and the stations they have served.
Future<void> showWorkerRecord(BuildContext context, Map<String, dynamic> worker) {
  return showDialog(context: context, builder: (_) => _WorkerRecordDialog(worker: worker));
}

class _WorkerRecordDialog extends StatefulWidget {
  const _WorkerRecordDialog({required this.worker});

  final Map<String, dynamic> worker;

  @override
  State<_WorkerRecordDialog> createState() => _WorkerRecordDialogState();
}

class _WorkerRecordDialogState extends State<_WorkerRecordDialog> {
  final _supabase = Supabase.instance.client;
  late final Future<List<dynamic>> _future = Future.wait([
    _supabase.from('worker_credentials').select('credential_type, status').eq('worker_id', widget.worker['id'] as String),
    _supabase
        .from('worker_incidents')
        .select('incident_type, description, status, created_at')
        .eq('worker_id', widget.worker['id'] as String)
        .order('created_at', ascending: false),
    _supabase.rpc('hire_check_station_history', params: {'p_worker_id': widget.worker['id']}),
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, yyyy');
    String words(String? s) => (s ?? '').replaceAll('_', ' ');

    return AlertDialog(
      title: Text(widget.worker['full_name'] as String? ?? 'Worker'),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) return Text('Could not load the record. ${describeError(snap.error!)}');
            final credentials = List<Map<String, dynamic>>.from(snap.data![0] as List);
            final incidents = List<Map<String, dynamic>>.from(snap.data![1] as List);
            final history = List<Map<String, dynamic>>.from(snap.data![2] as List);

            Widget heading(String t) => Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Text(t.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                );

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.worker['worker_code'] ?? ''} · clearance: ${words(widget.worker['clearance_status'] as String?)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  heading('Credentials'),
                  if (credentials.isEmpty) const Text('None on file.'),
                  for (final c in credentials) Text('${words(c['credential_type'] as String?)}: ${words(c['status'] as String?)}'),
                  heading('Incidents'),
                  if (incidents.isEmpty) const Text('No incidents filed.'),
                  for (final i in incidents)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${fmt.format(DateTime.parse(i['created_at'] as String).toLocal())} · ${i['incident_type']} '
                        '(${words(i['status'] as String?)}): ${i['description']}',
                      ),
                    ),
                  heading('Station history'),
                  if (history.isEmpty) const Text('No station history recorded.'),
                  for (final h in history)
                    Text(
                      '${h['station_name']}: ${fmt.format(DateTime.parse(h['joined_at'] as String).toLocal())}'
                      ' to ${h['left_at'] == null ? 'now' : fmt.format(DateTime.parse(h['left_at'] as String).toLocal())}'
                      ' (${words(h['status'] as String?)})',
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
