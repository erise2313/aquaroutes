import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_palette.dart';
import '../../constants/brand_tokens.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';

/// Official notices from WASA to one station or to every station, with
/// read and acknowledgement receipts -- "proof of who was told what",
/// which the rollout plan names as one of the association's problems with
/// paper. Sent through send_notice (supabase/patch_compliance.sql), which
/// also notifies each owner.
class AdminNoticesScreen extends StatefulWidget {
  const AdminNoticesScreen({super.key});

  @override
  State<AdminNoticesScreen> createState() => _AdminNoticesScreenState();
}

class _AdminNoticesScreenState extends State<AdminNoticesScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _notices = [];
  Map<String, String> _stations = {};
  int _activeStations = 0;

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
      final notices = await _supabase
          .from('notices')
          .select('id, title, body, station_id, requires_ack, created_at, notice_receipts(profile_id, read_at, acknowledged_at)')
          .order('created_at', ascending: false);
      final stations = await _supabase.from('water_stations').select('id, station_name, is_active, owner_profile_id');
      if (!mounted) return;
      setState(() {
        _notices = List<Map<String, dynamic>>.from(notices);
        _stations = {for (final s in stations) s['id'] as String: (s['station_name'] as String?) ?? 'Station'};
        _activeStations = stations.where((s) => s['is_active'] == true && s['owner_profile_id'] != null).length;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load notices. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _compose() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ComposeNoticeDialog(stations: _stations),
    );
    if (sent == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminPageHeader(
          eyebrow: 'Compliance',
          title: 'Official notices',
          subtitle: 'Written notices to stations, with who read and acknowledged them',
          actions: [
            FilledButton.icon(onPressed: _compose, icon: const Icon(Icons.campaign_outlined), label: const Text('New notice')),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : _notices.isEmpty
                      ? const PortalEmptyState(
                          icon: Icons.campaign_outlined,
                          title: 'No notices sent yet',
                          message: 'A notice reaches each owner as a notification and stays in their Notices page until acknowledged.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [for (final n in _notices) _buildTile(n)],
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> n) {
    final palette = AdminPalette.of(context);
    final receipts = List<Map<String, dynamic>>.from(n['notice_receipts'] as List? ?? const []);
    final read = receipts.length;
    final acked = receipts.where((r) => r['acknowledged_at'] != null).length;
    final audience = n['station_id'] == null ? _activeStations : 1;
    final to = n['station_id'] == null ? 'All stations' : (_stations[n['station_id']] ?? 'One station');
    return PortalCard(
      lift: false,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n['title'] as String, style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink)),
          Text(
            '$to · ${DateFormat('MMM d, yyyy').format(DateTime.parse(n['created_at'] as String).toLocal())}',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(n['body'] as String, style: TextStyle(color: palette.ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(label: 'Read by $read of $audience', color: Theme.of(context).colorScheme.primary, icon: Icons.visibility_outlined),
              if (n['requires_ack'] == true)
                StatusPill(
                  label: 'Acknowledged by $acked of $audience',
                  color: acked >= audience ? BrandStatus.success : BrandStatus.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeNoticeDialog extends StatefulWidget {
  const _ComposeNoticeDialog({required this.stations});

  final Map<String, String> stations;

  @override
  State<_ComposeNoticeDialog> createState() => _ComposeNoticeDialogState();
}

class _ComposeNoticeDialogState extends State<_ComposeNoticeDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _stationId;
  bool _requiresAck = true;
  bool _sending = false;

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write a title and the notice itself.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.rpc('send_notice', params: {
        'p_title': _title.text.trim(),
        'p_body': _body.text.trim(),
        'p_station_id': _stationId,
        'p_requires_ack': _requiresAck,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = widget.stations.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return AlertDialog(
      title: const Text('New official notice'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _stationId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Send to'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All stations')),
                  for (final s in sorted) DropdownMenuItem<String?>(value: s.key, child: Text(s.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _stationId = v),
              ),
              const SizedBox(height: 12),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(controller: _body, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Notice')),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _requiresAck,
                onChanged: (v) => setState(() => _requiresAck = v),
                title: const Text('Ask owners to acknowledge it'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _sending ? null : _send, child: const Text('Send notice')),
      ],
    );
  }
}
