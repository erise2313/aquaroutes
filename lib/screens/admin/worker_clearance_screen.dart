import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/admin_theme.dart';
import '../../constants/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';
import '../../constants/admin_palette.dart';

/// wasa_admin review of worker security incidents AND worker credential
/// submissions (Government ID / Driver's License), in two tabs. Confirming
/// an incident ('confirmed_flag') is what actually sets a worker's
/// clearance_status to 'flagged' -- dismissing restores it to 'cleared'
/// (apply_incident_resolution() trigger, 0005_workers.sql). Approving both
/// credentials flips a worker to 'cleared' automatically
/// (recompute_worker_clearance() trigger) unless they're already flagged.
/// Station owners can only file incidents/see credential status
/// (screens/merchant/worker_registry_screen.dart, driver_profile_screen.dart
/// for upload); only an admin can resolve either.
class WorkerClearanceScreen extends StatefulWidget {
  const WorkerClearanceScreen({super.key, this.initialTabIndex = 0});

  /// 0 = Incidents, 1 = Credentials -- lets a caller (e.g. the admin
  /// dashboard's review queue) land directly on the tab matching what was
  /// actually tapped, instead of always opening on Incidents.
  final int initialTabIndex;

  @override
  State<WorkerClearanceScreen> createState() => _WorkerClearanceScreenState();
}

class _WorkerClearanceScreenState extends State<WorkerClearanceScreen> {
  final _supabase = Supabase.instance.client;
  final _credentialService = WorkerCredentialService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _credentials = [];

  /// Credential ids ticked for a batch decision. Clearing a backlog one
  /// confirm dialog at a time was the single most repetitive job in the
  /// portal -- forty pending credentials meant forty dialogs.
  final Set<String> _selectedCredentials = {};
  bool _bulkInProgress = false;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final incidents = await _supabase
          .from('worker_incidents')
          .select('*, workers(full_name, worker_code, water_stations(station_name))')
          .eq('status', 'pending_review')
          .order('created_at');
      final credentials = await _supabase
          .from('worker_credentials')
          .select('*, workers(full_name, worker_code)')
          .eq('status', 'pending_review')
          .order('uploaded_at');
      if (mounted) {
        setState(() {
          _incidents = List<Map<String, dynamic>>.from(incidents);
          _credentials = List<Map<String, dynamic>>.from(credentials);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the review queue. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resolveIncident(String incidentId, bool confirmFlag) async {
    if (confirmFlag) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Confirm Flag?',
        message: 'This will flag the worker, blocking their clearance until WASA resolves it.',
        confirmLabel: 'Confirm Flag',
      );
      if (!confirmed) return;
    }

    try {
      await _supabase.from('worker_incidents').update({
        'status': confirmFlag ? 'confirmed_flag' : 'dismissed',
        'resolved_by': _supabase.auth.currentUser!.id,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', incidentId);
      await _fetchAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resolve incident. ${describeError(e)}')));
    }
  }

  Future<void> _reviewCredential(String credentialId, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _promptRejectionReason();
      if (reason == null) return;
    }
    try {
      await _credentialService.reviewCredential(
        credentialId: credentialId,
        approve: approve,
        reviewedByProfileId: _supabase.auth.currentUser!.id,
        rejectionReason: reason,
      );
      await _fetchAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not review credential. ${describeError(e)}')));
    }
  }

  /// Applies one decision to every ticked credential. Failures are counted
  /// rather than swallowed or allowed to abort the run: a batch that stops
  /// halfway with no report leaves the admin unable to tell which ones went
  /// through.
  Future<void> _bulkReviewCredentials(bool approve) async {
    final ids = _selectedCredentials.toList();
    if (ids.isEmpty) return;

    String? reason;
    if (!approve) {
      reason = await _promptRejectionReason();
      if (reason == null) return;
    } else {
      if (!mounted) return;
      final confirmed = await showConfirmDialog(
        context,
        title: 'Approve ${ids.length} credential${ids.length == 1 ? '' : 's'}?',
        message: 'Each worker whose documents are then complete is cleared automatically.',
        confirmLabel: 'Approve all',
      );
      if (!confirmed) return;
    }

    setState(() => _bulkInProgress = true);
    var succeeded = 0;
    final failures = <String>[];
    for (final id in ids) {
      try {
        await _credentialService.reviewCredential(
          credentialId: id,
          approve: approve,
          reviewedByProfileId: _supabase.auth.currentUser!.id,
          rejectionReason: reason,
        );
        succeeded++;
      } catch (e) {
        failures.add('$id. ${describeError(e)}');
      }
    }

    if (!mounted) return;
    setState(() {
      _bulkInProgress = false;
      _selectedCredentials.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? '$succeeded credential${succeeded == 1 ? '' : 's'} ${approve ? 'approved' : 'rejected'}.'
              : '$succeeded of ${ids.length} processed. ${failures.length} failed -- they are still in the list.',
        ),
      ),
    );
    await _fetchAll();
  }

  Future<String?> _promptRejectionReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejection Reason'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Why is this being rejected?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
  }

  Future<void> _viewCredentialDocument(String? storagePath) async {
    if (storagePath == null) return;
    try {
      final url = await _credentialService.getSignedUrl(storagePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open document. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex,
      child: Column(
        children: [
          AdminPageHeader(
            eyebrow: 'Association',
            title: 'Worker Clearance Review',
            subtitle: 'Incidents filed by stations, and credentials waiting on a decision',
            bottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: AdminTheme.sealGold,
              indicatorWeight: 3,
              tabs: [
                Tab(text: 'Incidents (${_incidents.length})'),
                Tab(text: 'Credentials (${_credentials.length})'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                ? ErrorState(message: _error!, onRetry: _fetchAll)
                : TabBarView(
                    children: [
                      _incidents.isEmpty
                          ? const PortalEmptyState(
                              icon: Icons.verified_user_outlined,
                              title: 'No incidents awaiting review',
                              message: 'Every incident a station has filed has been confirmed or dismissed.',
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchAll,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _incidents.length,
                                itemBuilder: (context, index) => _buildIncidentCard(_incidents[index]),
                              ),
                            ),
                      _credentials.isEmpty
                          ? const PortalEmptyState(
                              icon: Icons.badge_outlined,
                              title: 'No credentials awaiting review',
                              message: 'Every ID and licence submitted so far has been approved or rejected.',
                            )
                          : Column(
                              children: [
                                _buildSelectionBar(),
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: _fetchAll,
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _credentials.length,
                                      itemBuilder: (context, index) => _buildCredentialCard(_credentials[index]),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Select-all plus the batch actions. Always visible (not only once
  /// something is ticked) so the capability is discoverable rather than
  /// hidden behind a long-press nobody would try.
  Widget _buildSelectionBar() {
    final allIds = _credentials.map((c) => c['id'] as String).toSet();
    final allSelected = allIds.isNotEmpty && _selectedCredentials.containsAll(allIds);
    final count = _selectedCredentials.length;

    return Material(
      color: AdminPalette.of(context).foam,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
        child: Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: false,
              onChanged: _bulkInProgress
                  ? null
                  : (v) => setState(() {
                        _selectedCredentials
                          ..clear()
                          ..addAll(v == true ? allIds : const <String>[]);
                      }),
            ),
            Expanded(
              child: Text(
                count == 0 ? 'Select all' : '$count selected',
                style: TextStyle(fontWeight: FontWeight.w600, color: AdminPalette.of(context).ink),
              ),
            ),
            if (_bulkInProgress)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              TextButton(
                onPressed: count == 0 ? null : () => _bulkReviewCredentials(false),
                child: const Text('Reject'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.cleared, minimumSize: const Size(0, 44)),
                onPressed: count == 0 ? null : () => _bulkReviewCredentials(true),
                child: const Text('Approve'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> incident) {
    final worker = incident['workers'] as Map<String, dynamic>?;
    final station = worker?['water_stations'] as Map<String, dynamic>?;
    final amount = incident['amount_involved'];

    final palette = AdminPalette.of(context);

    return PortalCard(
      lift: false,
      accent: AppColors.pendingClearance,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            worker?['full_name'] ?? 'Unknown Worker',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: palette.ink),
          ),
          Text(
            '${worker?['worker_code'] ?? ''} · ${station?['station_name'] ?? 'Unknown Station'}',
            style: TextStyle(color: palette.inkMuted),
          ),
          const SizedBox(height: 8),
          // The pill was a non-flexible child of a Row beside an Expanded
          // name, so it was laid out with unbounded width and its label could
          // never wrap. Here its width is bounded.
          const AdminStatusPill(label: 'PENDING REVIEW', color: AppColors.pendingClearance),
          const SizedBox(height: 8),
          Text('Type: ${incident['incident_type']}'),
          if (amount != null) Text('Amount involved: ₱$amount'),
          const SizedBox(height: 4),
          Text(incident['description'] ?? ''),
          const SizedBox(height: 12),
          PortalActionRow(
            children: [
              OutlinedButton(
                onPressed: () => _resolveIncident(incident['id'] as String, false),
                child: const Text('Dismiss'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.flagged),
                onPressed: () => _resolveIncident(incident['id'] as String, true),
                child: const Text('Confirm flag'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialCard(Map<String, dynamic> credential) {
    final worker = credential['workers'] as Map<String, dynamic>?;
    final label = credential['credential_type'] == 'drivers_license' ? "Driver's License" : 'Government-Issued ID';
    final storagePath = credential['storage_path'] as String?;
    final id = credential['id'] as String;
    final selected = _selectedCredentials.contains(id);

    final palette = AdminPalette.of(context);

    return PortalCard(
      lift: false,
      accent: selected ? AdminTheme.harborBlue : AppColors.pendingClearance,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: _bulkInProgress
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _selectedCredentials.add(id);
                          } else {
                            _selectedCredentials.remove(id);
                          }
                        }),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker?['full_name'] ?? 'Unknown Worker',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: palette.ink),
                    ),
                    Text(worker?['worker_code'] ?? '', style: TextStyle(color: palette.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const AdminStatusPill(label: 'PENDING REVIEW', color: AppColors.pendingClearance),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text('Document: $label')),
              if (storagePath != null)
                TextButton.icon(
                  onPressed: () => _viewCredentialDocument(storagePath),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          PortalActionRow(
            children: [
              OutlinedButton(
                onPressed: () => _reviewCredential(credential['id'] as String, false),
                child: const Text('Reject'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.cleared),
                onPressed: () => _reviewCredential(credential['id'] as String, true),
                child: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
