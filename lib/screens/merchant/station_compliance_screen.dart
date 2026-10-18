import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/brand_tokens.dart';
import '../../utils/error_text.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';

/// How many notices addressed to the owner's station are not yet
/// acknowledged -- the sidebar badge on "WASA notices".
final unacknowledgedNoticesProvider = FutureProvider.autoDispose<int>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return 0;
  final notices = await client.from('notices').select('id, requires_ack');
  final receipts = await client.from('notice_receipts').select('notice_id, acknowledged_at').eq('profile_id', userId);
  final acknowledged = {for (final r in receipts) if (r['acknowledged_at'] != null) r['notice_id'] as String};
  return notices.where((n) => n['requires_ack'] == true && !acknowledged.contains(n['id'])).length;
});

const _caseKinds = {
  'permit': 'Permit',
  'water_test': 'Water test',
  'conduct': 'Conduct',
  'complaint': 'Customer complaint',
};
const _caseStatuses = {
  'open': 'Open',
  'warning_issued': 'Warning issued',
  'board_action': 'Referred to the board',
  'resolved': 'Resolved',
};

/// The station's side of its record with the association: official notices
/// from WASA (read and acknowledge) and compliance cases (read the record,
/// write a response). Both come from supabase/patch_compliance.sql.
class StationComplianceScreen extends ConsumerStatefulWidget {
  const StationComplianceScreen({super.key});

  @override
  ConsumerState<StationComplianceScreen> createState() => _StationComplianceScreenState();
}

class _StationComplianceScreenState extends ConsumerState<StationComplianceScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _notices = [];
  Map<String, Map<String, dynamic>> _receipts = {};
  List<Map<String, dynamic>> _cases = [];

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
      final notices = await _supabase.from('notices').select().order('created_at', ascending: false);
      final receipts = await _supabase.from('notice_receipts').select().eq('profile_id', userId);
      final cases = await _supabase.from('compliance_cases').select().order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _notices = List<Map<String, dynamic>>.from(notices);
        _receipts = {for (final r in receipts) r['notice_id'] as String: r};
        _cases = List<Map<String, dynamic>>.from(cases);
        _isLoading = false;
      });
      // Opening the page counts as reading every notice on it.
      for (final n in _notices) {
        if (!_receipts.containsKey(n['id'])) {
          _supabase.rpc('mark_notice', params: {'p_notice_id': n['id'], 'p_acknowledge': false}).ignore();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acknowledge(Map<String, dynamic> notice) async {
    try {
      await _supabase.rpc('mark_notice', params: {'p_notice_id': notice['id'], 'p_acknowledge': true});
      ref.invalidate(unacknowledgedNoticesProvider);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _respond(Map<String, dynamic> c) async {
    final controller = TextEditingController(text: c['station_response'] as String?);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your response'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['summary'] as String),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Explain what happened and what you did about it'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Send response')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await _supabase.rpc('respond_to_case', params: {'p_case_id': c['id'], 'p_response': text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Response sent to WASA.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final openCases = _cases.where((c) => c['status'] != 'resolved').length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            PortalPageHeader(
              eyebrow: 'Your station',
              title: 'WASA notices',
              subtitle: 'Official notices from the association, and any compliance case about your station',
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Notices (${_notices.length})'),
                  Tab(text: 'Cases${openCases > 0 ? ' ($openCases open)' : ''}'),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ErrorState(message: _error!, onRetry: _load)
                      : TabBarView(children: [_buildNotices(), _buildCases()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotices() {
    final theme = Theme.of(context);
    if (_notices.isEmpty) {
      return const PortalEmptyState(
        icon: Icons.campaign_outlined,
        title: 'No notices',
        message: 'Official notices from WASA -- meetings, new requirements, deadlines -- appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: PortalDensity.of(context).pagePadding,
        children: [
          for (final n in _notices)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n['title'] as String, style: theme.textTheme.titleMedium),
                  Text(DateFormat('MMM d, yyyy').format(DateTime.parse(n['created_at'] as String).toLocal()),
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(n['body'] as String),
                  if (n['requires_ack'] == true) ...[
                    const SizedBox(height: 10),
                    if (_receipts[n['id']]?['acknowledged_at'] != null)
                      StatusPill(
                        label: 'Acknowledged ${DateFormat('MMM d').format(DateTime.parse(_receipts[n['id']]!['acknowledged_at'] as String).toLocal())}',
                        color: BrandStatus.success,
                      )
                    else
                      FilledButton.icon(
                        onPressed: () => _acknowledge(n),
                        icon: const Icon(Icons.check),
                        label: const Text('I have read this'),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCases() {
    final theme = Theme.of(context);
    if (_cases.isEmpty) {
      return const PortalEmptyState(
        icon: Icons.verified_outlined,
        title: 'No compliance cases',
        message: 'If WASA opens a case about your station -- a missing permit, a late water test, a complaint -- '
            'it appears here and you can answer it in writing.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: PortalDensity.of(context).pagePadding,
        children: [
          for (final c in _cases)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(_caseKinds[c['kind']] ?? '', style: theme.textTheme.titleMedium),
                      StatusPill(
                        label: _caseStatuses[c['status']] ?? '',
                        color: switch (c['status']) {
                          'resolved' => BrandStatus.success,
                          'board_action' => BrandStatus.danger,
                          'warning_issued' => BrandStatus.warning,
                          _ => BrandStatus.info,
                        },
                      ),
                    ],
                  ),
                  Text('Opened ${DateFormat('MMM d, yyyy').format(DateTime.parse(c['created_at'] as String).toLocal())}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(c['summary'] as String),
                  if (c['evidence'] != null) ...[
                    const SizedBox(height: 4),
                    Text('Evidence: ${c['evidence']}', style: theme.textTheme.bodySmall),
                  ],
                  if (c['decision'] != null) ...[
                    const SizedBox(height: 6),
                    Text('WASA\'s decision: ${c['decision']}', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                  if (c['station_response'] != null) ...[
                    const SizedBox(height: 6),
                    Text('Your response: ${c['station_response']}', style: theme.textTheme.bodySmall),
                  ],
                  if (c['status'] != 'resolved') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _respond(c),
                      icon: const Icon(Icons.edit_note),
                      label: Text(c['station_response'] == null ? 'Respond in writing' : 'Edit your response'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
