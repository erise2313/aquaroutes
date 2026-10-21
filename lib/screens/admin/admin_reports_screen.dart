import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/admin_palette.dart';
import '../../constants/brand_tokens.dart';
import '../../providers/admin_queue_provider.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/report_problem_dialog.dart';
import '../../widgets/officer_can.dart';
import 'admin_orders_screen.dart' show showReportedOrder;

const adminReportsSelect = 'id, station_id, order_id, category, details, photo_path, status, officer_note, '
    'station_response, responded_at, created_at, resolved_at, '
    'water_stations(station_name), '
    'profiles!station_reports_reporter_id_fkey(full_name, phone_number)';

Color reportStatusColor(String? status) => switch (status) {
      'resolved' => BrandStatus.success,
      'dismissed' => Colors.blueGrey,
      'reviewing' => BrandStatus.warning,
      _ => BrandStatus.info,
    };

/// Narrows reports by status ("open" = new or reviewing) and by a search
/// over the station, what was reported and the reporter. Pure, for tests.
List<Map<String, dynamic>> filterAdminReports(List<Map<String, dynamic>> rows, {String? status, String query = ''}) {
  final q = query.trim().toLowerCase();
  return rows.where((r) {
    if (status == 'open' && !(r['status'] == 'new' || r['status'] == 'reviewing')) return false;
    if (status != null && status != 'open' && r['status'] != status) return false;
    if (q.isEmpty) return true;
    return [
      r['water_stations']?['station_name'] as String?,
      r['details'] as String?,
      stationReportCategories[r['category']],
      r['profiles']?['full_name'] as String?,
    ].any((f) => f != null && f.toLowerCase().contains(q));
  }).toList();
}

/// Customer reports to the association about a station: water quality,
/// jugs, deliveries, driver conduct (patch_public_trust.sql). Officers see
/// who filed each one -- the station never does -- and can update its status
/// with a note the customer is notified of, or open a compliance case from
/// it. A report about an order also unlocks that order's customer details
/// via "View the order".
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  final _supabase = Supabase.instance.client;
  final _search = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  String _query = '';
  String? _status = 'open';

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
      final rows = await _supabase.from('station_reports').select(adminReportsSelect).order('created_at', ascending: false).limit(500);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load reports. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openPhoto(String path) async {
    try {
      final url = await _supabase.storage.from('station-reports').createSignedUrl(path, 300);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the photo. ${describeError(e)}')));
    }
  }

  Future<void> _update(Map<String, dynamic> report) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ReportDialog(report: report));
    if (saved == true) {
      ref.invalidate(adminQueueCountsProvider);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterAdminReports(_reports, status: _status, query: _query);
    return Column(
      children: [
        const AdminPageHeader(
          eyebrow: 'Compliance',
          title: 'Customer reports',
          subtitle: 'Problems customers reported to WASA about a station. The station sees the report, never who filed it.',
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : Column(
                      children: [
                        AdminFilterBar(
                          searchHint: 'Search by station, problem or customer',
                          searchController: _search,
                          onSearchChanged: (v) => setState(() => _query = v),
                          filters: [
                            AdminFilterGroup(
                              label: 'Status',
                              options: {'open': 'Needs attention', null: 'All', ...stationReportStatuses},
                              selected: _status,
                              onChanged: (v) => setState(() => _status = v),
                            ),
                          ],
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? const PortalEmptyState(
                                  icon: Icons.flag_outlined,
                                  title: 'No reports here',
                                  message: 'When a customer reports a problem with a station from the app, it appears here.',
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                    children: [for (final r in visible) _buildTile(r)],
                                  ),
                                ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> r) {
    final palette = AdminPalette.of(context);
    final fmt = DateFormat('MMM d, yyyy h:mm a');
    final reporter = r['profiles'] as Map<String, dynamic>?;
    return PortalCard(
      margin: const EdgeInsets.only(bottom: 10),
      accent: reportStatusColor(r['status'] as String?),
      // Only roles that may change compliance records can open the update
      // form; others read the report as it is.
      onTap: switch (currentOfficerRole(ref)) {
        final role? when !officerAreaAllowed(role, OfficerArea.stations) => null,
        _ => () => _update(r),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text((r['water_stations']?['station_name'] as String?) ?? 'Station', style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink)),
              StatusPill(label: stationReportStatuses[r['status']] ?? '', color: reportStatusColor(r['status'] as String?)),
            ],
          ),
          Text(
            '${stationReportCategories[r['category']] ?? r['category']} · ${fmt.format(DateTime.parse(r['created_at'] as String).toLocal())}'
            '${r['order_id'] != null ? ' · about order #${(r['order_id'] as String).substring(0, 6).toUpperCase()}' : ''}',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(r['details'] as String, style: TextStyle(color: palette.ink)),
          const SizedBox(height: 4),
          Text(
            'Filed by ${(reporter?['full_name'] as String?) ?? 'a customer'}'
            '${reporter?['phone_number'] != null ? ' · ${reporter!['phone_number']}' : ''}',
            style: TextStyle(color: palette.inkMuted),
          ),
          if (r['station_response'] != null) ...[
            const SizedBox(height: 6),
            Text('Station\'s response: ${r['station_response']}', style: TextStyle(color: palette.inkMuted, fontStyle: FontStyle.italic)),
          ],
          if (r['officer_note'] != null) ...[
            const SizedBox(height: 6),
            Text('WASA note: ${r['officer_note']}', style: TextStyle(color: palette.ink)),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (r['photo_path'] != null)
                TextButton.icon(
                  onPressed: () => _openPhoto(r['photo_path'] as String),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('View photo'),
                ),
              // The only way an officer sees an order: through a report
              // about it.
              if (r['order_id'] != null)
                TextButton.icon(
                  onPressed: () => showReportedOrder(context, r['order_id'] as String),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View the order'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.report});

  final Map<String, dynamic> report;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late String _status = widget.report['status'] as String;
  late final _note = TextEditingController(text: widget.report['officer_note'] as String?);
  bool _openCase = false;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if ((_status == 'resolved' || _status == 'dismissed') && _note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write a note for the customer saying what was done.')));
      return;
    }
    setState(() => _saving = true);
    final client = Supabase.instance.client;
    final r = widget.report;
    try {
      await client.from('station_reports').update({
        'status': _status,
        'officer_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      }).eq('id', r['id'] as String);
      if (_openCase) {
        await client.from('compliance_cases').insert({
          'station_id': r['station_id'],
          'kind': 'complaint',
          'summary': '${stationReportCategories[r['category']] ?? 'Customer report'}: ${r['details']}',
          'evidence': 'Customer report filed ${DateFormat('MMM d, yyyy').format(DateTime.parse(r['created_at'] as String).toLocal())}'
              '${r['photo_path'] != null ? ', with a photo' : ''}.',
          'status': 'open',
        });
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
    final r = widget.report;
    return AlertDialog(
      title: Text('Report about ${(r['water_stations']?['station_name'] as String?) ?? 'a station'}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(stationReportCategories[r['category']] ?? '', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(r['details'] as String),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final s in stationReportStatuses.entries) DropdownMenuItem(value: s.key, child: Text(s.value))],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Note to the customer (sent when the status changes)'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _openCase,
                onChanged: (v) => setState(() => _openCase = v ?? false),
                contentPadding: EdgeInsets.zero,
                title: const Text('Also open a compliance case for this station'),
                subtitle: const Text('For a problem that needs a written record and a decision.'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
