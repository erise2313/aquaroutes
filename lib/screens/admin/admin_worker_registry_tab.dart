import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/rejection_reason_dialog.dart';
import '../../widgets/officer_can.dart';
import '../../widgets/skeleton_loader.dart';

/// Every worker across all member stations, with their clearance -- the
/// association-wide registry an officer is responsible for.
///
/// The Workers section used to show only the review queues, so an officer
/// could not answer "who is flagged right now?" or look up one driver's
/// record without waiting for something about them to land in a queue.
class AdminWorkerRegistryTab extends StatefulWidget {
  const AdminWorkerRegistryTab({super.key, this.initialClearance});

  /// Pre-selects the clearance filter ('flagged', 'cleared',
  /// 'pending_clearance') -- the Overview's "Flagged workers" tile.
  final String? initialClearance;

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
    _clearance = widget.initialClearance;
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
                onTap: () async {
                  if (await showWorkerRecord(context, w)) _load();
                },
                child: Builder(builder: (context) {
                  // On a phone the pill goes under the name: beside it, it
                  // squeezed the worker code into a narrow column.
                  final narrow = MediaQuery.sizeOf(context).width < 480;
                  final pill = StatusPill(
                    label: _clearanceLabels[w['clearance_status']] ?? 'Unknown',
                    color: _colorFor(w['clearance_status'] as String?),
                  );
                  return Row(
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
                          if (narrow) ...[const SizedBox(height: 6), pill],
                        ],
                      ),
                    ),
                    if (!narrow) pill,
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  ],
                );
                }),
              ),
        ],
      ),
    );
  }
}

/// One worker's full record for an officer: clearance, credentials, every
/// incident and the stations they have served -- and the decisions an
/// officer can take from it.
///
/// It used to be read-only. The review queues only hold items still waiting
/// for a decision, so once an incident was confirmed nothing in the portal
/// could lift the flag again (only the driver's own appeal could), and a
/// credential could not be opened or reviewed from the worker it belongs to.
///
/// Resolves to true when something was changed, so the list can refresh.
Future<bool> showWorkerRecord(BuildContext context, Map<String, dynamic> worker) async {
  final changed = await showDialog<bool>(context: context, builder: (_) => _WorkerRecordDialog(worker: worker));
  return changed ?? false;
}

class _WorkerRecordDialog extends StatefulWidget {
  const _WorkerRecordDialog({required this.worker});

  final Map<String, dynamic> worker;

  @override
  State<_WorkerRecordDialog> createState() => _WorkerRecordDialogState();
}

class _WorkerRecordDialogState extends State<_WorkerRecordDialog> {
  final _supabase = Supabase.instance.client;
  final _credentialService = WorkerCredentialService(SupabaseService.instance);
  late Future<List<dynamic>> _future = _fetch();
  bool _changed = false;
  bool _busy = false;

  String get _workerId => widget.worker['id'] as String;

  Future<List<dynamic>> _fetch() => Future.wait([
        _supabase.from('workers').select('clearance_status').eq('id', _workerId).single(),
        _supabase
            .from('worker_credentials')
            .select('id, credential_type, status, storage_path, rejection_reason, expiry_date')
            .eq('worker_id', _workerId),
        _supabase
            .from('worker_incidents')
            .select('id, incident_type, description, status, created_at, appeal_status')
            .eq('worker_id', _workerId)
            .order('created_at', ascending: false),
        _supabase.rpc('hire_check_station_history', params: {'p_worker_id': _workerId}),
      ]);

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      if (mounted) setState(() => _future = _fetch());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$failure ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sets an incident's outcome. Dismissing a confirmed one lifts the flag:
  /// the database recomputes the worker's clearance from what remains, and
  /// the audit log records who did it.
  Future<void> _setIncident(Map<String, dynamic> incident, String status) async {
    final (title, message, label) = switch ((incident['status'], status)) {
      ('confirmed_flag', 'dismissed') => (
          'Lift this flag?',
          'The incident is dismissed and the worker is cleared again unless another confirmed incident remains. '
              'Use this when an incident was confirmed in error or has been resolved.',
          'Lift flag',
        ),
      (_, 'confirmed_flag') => (
          'Confirm flag?',
          'This flags the worker across every station until WASA resolves it.',
          'Confirm flag',
        ),
      _ => ('Dismiss incident?', 'The incident is closed with no flag.', 'Dismiss'),
    };
    final ok = await showConfirmDialog(context, title: title, message: message, confirmLabel: label);
    if (!ok) return;
    await _run(
      () => _supabase.from('worker_incidents').update({
        'status': status,
        'resolved_by': _supabase.auth.currentUser!.id,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', incident['id'] as String),
      'Could not update the incident.',
    );
  }

  Future<void> _reviewCredential(Map<String, dynamic> credential, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await promptRejectionReason(context);
      if (reason == null) return;
    }
    await _run(
      () => _credentialService.reviewCredential(
        credentialId: credential['id'] as String,
        approve: approve,
        reviewedByProfileId: _supabase.auth.currentUser!.id,
        rejectionReason: reason,
      ),
      'Could not review the credential.',
    );
  }

  Future<void> _openDocument(String storagePath) async {
    try {
      final url = await _credentialService.getSignedUrl(storagePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open document. ${describeError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, yyyy');
    String words(String? s) => (s ?? '').replaceAll('_', ' ');

    return AlertDialog(
      title: Text(widget.worker['full_name'] as String? ?? 'Worker'),
      content: SizedBox(
        width: 600,
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) return Text('Could not load the record. ${describeError(snap.error!)}');
            final clearance = (snap.data![0] as Map)['clearance_status'] as String?;
            final credentials = List<Map<String, dynamic>>.from(snap.data![1] as List);
            final incidents = List<Map<String, dynamic>>.from(snap.data![2] as List);
            final history = List<Map<String, dynamic>>.from(snap.data![3] as List);

            Widget heading(String t) => Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Text(t.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                );

            Widget item({required String text, String? note, List<Widget> actions = const []}) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text),
                      if (note != null)
                        Text(note, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      if (actions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(spacing: 8, runSpacing: 8, children: actions),
                        ),
                    ],
                  ),
                );

            return AbsorbPointer(
              absorbing: _busy,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${widget.worker['worker_code'] ?? ''} · clearance', style: theme.textTheme.bodyMedium),
                        StatusPill(
                          label: _AdminWorkerRegistryTabState._clearanceLabels[clearance] ?? 'Unknown',
                          color: _AdminWorkerRegistryTabState._colorFor(clearance),
                        ),
                      ],
                    ),
                    heading('Credentials'),
                    if (credentials.isEmpty) const Text('None on file.'),
                    for (final c in credentials)
                      item(
                        text: '${words(c['credential_type'] as String?)}: ${words(c['status'] as String?)}',
                        note: [
                          if (c['expiry_date'] != null) 'Expires ${fmt.format(DateTime.parse(c['expiry_date'] as String))}',
                          if (c['status'] == 'rejected' && c['rejection_reason'] != null) 'Reason: ${c['rejection_reason']}',
                        ].join(' · ').ifEmptyNull,
                        actions: [
                          if (c['storage_path'] != null)
                            TextButton.icon(
                              onPressed: () => _openDocument(c['storage_path'] as String),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('View document'),
                            ),
                          if (c['status'] == 'pending_review') ...[
                            OfficerCan(area: OfficerArea.workers, child: OutlinedButton(onPressed: () => _reviewCredential(c, false), child: const Text('Reject'))),
                            OfficerCan(area: OfficerArea.workers, child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.cleared),
                              onPressed: () => _reviewCredential(c, true),
                              child: const Text('Approve'),
                            )),
                          ],
                        ],
                      ),
                    heading('Incidents'),
                    if (incidents.isEmpty) const Text('No incidents filed.'),
                    for (final i in incidents)
                      item(
                        text: '${fmt.format(DateTime.parse(i['created_at'] as String).toLocal())} · ${i['incident_type']} '
                            '(${words(i['status'] as String?)}): ${i['description']}',
                        note: i['appeal_status'] == 'pending' ? 'The driver has appealed this -- see the Appeals tab.' : null,
                        actions: [
                          if (i['status'] == 'pending_review') ...[
                            OfficerCan(area: OfficerArea.workers, child: OutlinedButton(onPressed: () => _setIncident(i, 'dismissed'), child: const Text('Dismiss'))),
                            OfficerCan(area: OfficerArea.workers, child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.flagged),
                              onPressed: () => _setIncident(i, 'confirmed_flag'),
                              child: const Text('Confirm flag'),
                            )),
                          ],
                          if (i['status'] == 'confirmed_flag')
                            OfficerCan(area: OfficerArea.workers, child: OutlinedButton.icon(
                              onPressed: () => _setIncident(i, 'dismissed'),
                              icon: const Icon(Icons.flag_outlined, size: 18),
                              label: const Text('Lift flag'),
                            )),
                        ],
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
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Close'))],
    );
  }
}

extension on String {
  /// Null for an empty string, so an absent note isn't drawn as a blank line.
  String? get ifEmptyNull => isEmpty ? null : this;
}
