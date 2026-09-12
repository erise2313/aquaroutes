import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../utils/error_text.dart';

/// Station-owner side of the Worker Security Registry: share the station's
/// invite code so a worker can self-register as a driver, and file
/// incidents (missing cash, lost jugs, etc). A worker must have their own
/// account to ever upload the ID/license credentials clearance requires --
/// a raw owner-added record with no account can never legitimately clear,
/// so this screen deliberately has no "add worker" form, only the invite
/// code (register_driver_for_station() creates the real account). Filing an
/// incident immediately knocks the worker back to pending_clearance; only a
/// WASA admin can confirm it into 'flagged' or dismiss it (0005_workers.sql
/// triggers) -- this screen deliberately has no way to flag a worker
/// directly either.
class WorkerRegistryScreen extends StatefulWidget {
  const WorkerRegistryScreen({super.key});

  @override
  State<WorkerRegistryScreen> createState() => _WorkerRegistryScreenState();
}

class _WorkerRegistryScreenState extends State<WorkerRegistryScreen> {
  final _workerService = WorkerService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;
  final _incidentFormKey = GlobalKey<FormState>();

  String? _stationId;
  String? _inviteCode;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveStation();
  }

  Future<void> _resolveStation() async {
    final userId = _supabase.auth.currentUser!.id;
    final station = await _supabase.from('water_stations').select('id, invite_code').eq('owner_profile_id', userId).maybeSingle();
    if (mounted) {
      setState(() {
        _stationId = station?['id'] as String?;
        _inviteCode = station?['invite_code'] as String?;
        _isLoading = false;
      });
    }
  }

  void _showInviteCodeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Invite Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Workers now join by registering themselves with this code instead of being added directly, so they get '
              'their own account -- give this code to a new worker so they can register themselves as a driver at your '
              'station. This creates their own account, which they need to upload their Government ID and Driver\'s '
              'License for WASA clearance.',
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _inviteCode ?? '—',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton.icon(
            onPressed: _inviteCode == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _inviteCode!));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite code copied to clipboard.')));
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy Code'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFromRoster(Worker worker) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove from Roster',
      message: 'Remove ${worker.fullName} from your station? Any deliveries currently assigned to them will go back to the pending queue for reassignment. '
          'Their clearance/incident history is preserved -- they can be re-linked by a station anytime.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;

    try {
      await _workerService.removeWorkerFromRoster(worker.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${worker.fullName} removed from roster.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  void _showFileIncidentDialog(Worker worker) {
    String incidentType = 'missing_cash';
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('File Incident: ${worker.fullName}'),
          content: SingleChildScrollView(
            child: Form(
              key: _incidentFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submitting this will immediately move ${worker.fullName} back to Pending Clearance until WASA reviews it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: incidentType,
                    decoration: const InputDecoration(labelText: 'Incident Type'),
                    items: const [
                      DropdownMenuItem(value: 'missing_cash', child: Text('Missing Sales Cash')),
                      DropdownMenuItem(value: 'lost_jugs', child: Text('Lost/Stolen Jugs')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setDialogState(() => incidentType = v ?? incidentType),
                  ),
                  TextFormField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount Involved (₱, optional)'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return double.tryParse(v.trim()) == null ? 'Enter a valid number.' : null;
                    },
                  ),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'A description is required.' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.flagged),
              onPressed: () async {
                if (!_incidentFormKey.currentState!.validate()) return;
                try {
                  await _workerService.fileIncident(
                    workerId: worker.id,
                    reportedByProfileId: _supabase.auth.currentUser!.id,
                    incidentType: incidentType,
                    description: descriptionController.text.trim(),
                    amountInvolved: double.tryParse(amountController.text.trim()),
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not file incident. ${describeError(e)}')));
                  }
                }
              },
              child: const Text('Submit to WASA', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showIncidentHistory(Worker worker) {
    // Declared here, outside the rebuilding closures below, so a retry's
    // reassignment actually sticks -- redeclaring `future` inside the
    // StatefulBuilder's own `builder` (as this used to) gets re-run on
    // every setSheetState, silently discarding the retry's new future and
    // firing a second, redundant fetch instead.
    var future = _workerService.fetchIncidentsForWorker(worker.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<List<WorkerIncident>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorState(
                    message: 'Could not load incident history: ${snapshot.error}',
                    onRetry: () => setSheetState(() => future = _workerService.fetchIncidentsForWorker(worker.id)),
                  );
                }
                final incidents = snapshot.data ?? [];
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Incident history: ${worker.fullName}', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Expanded(
                        child: incidents.isEmpty
                            ? const PortalEmptyState(
                                icon: Icons.verified_user_outlined,
                                title: 'No incidents filed',
                                message: 'Nothing has been reported against this worker.',
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: incidents.length,
                                itemBuilder: (context, index) => _buildIncidentHistoryCard(incidents[index]),
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildIncidentHistoryCard(WorkerIncident incident) {
    final (color, label) = switch (incident.status) {
      IncidentStatus.confirmedFlag => (AppColors.flagged, 'Confirmed'),
      IncidentStatus.dismissed => (AppColors.cleared, 'Dismissed'),
      IncidentStatus.pendingReview => (AppColors.pendingClearance, 'Pending Review'),
    };

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PortalCard(
      lift: false,
      accent: color,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A Wrap rather than a Row: it bounds its children, so the pill's
          // label wraps instead of running off the sheet at large text.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(incident.incidentType, style: theme.textTheme.titleSmall),
              StatusPill(label: label.toUpperCase(), color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(incident.description, style: theme.textTheme.bodyMedium),
          if (incident.amountInvolved != null)
            Text('Amount involved: ${formatPeso(incident.amountInvolved!)}', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Filed ${DateFormat('MMM d, yyyy').format(incident.createdAt)}'
            '${incident.resolvedAt != null ? ' · Resolved ${DateFormat('MMM d, yyyy').format(incident.resolvedAt!)}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);

    return Scaffold(
      body: Column(
        children: [
          PortalPageHeader(
            eyebrow: 'Governance & compliance',
            title: 'Worker Registry',
            subtitle: 'Your drivers and helpers, and the incidents WASA reviews',
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share invite code',
                onPressed: _stationId == null ? null : _showInviteCodeDialog,
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stationId == null
                ? const PortalEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No station linked to this account',
                    message: 'Your account is not linked to a water station, so it has no worker roster.',
                  )
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _workerService.watchStationWorkers(_stationId!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final workers = snapshot.data!.map((m) => Worker.fromMap(m)).toList();
                      if (workers.isEmpty) {
                        return PortalEmptyState(
                          icon: Icons.badge_outlined,
                          title: 'No workers registered yet',
                          message: 'Workers join by registering themselves with your station\'s invite code, '
                              'so they get their own account and can upload the credentials WASA clearance needs.',
                          action: FilledButton.icon(
                            onPressed: _stationId == null ? null : _showInviteCodeDialog,
                            icon: const Icon(Icons.share),
                            label: const Text('Share invite code'),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: density.pagePadding,
                        itemCount: workers.length,
                        itemBuilder: (context, index) =>
                            _buildWorkerCard(workers[index], last: index == workers.length - 1, density: density),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(Worker worker, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (color, label) = switch (worker.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    // The actions stay in a Wrap. A ListTile with a trailing Column silently
    // overflowed here once there were three of them ("BOTTOM OVERFLOWED BY
    // 108 PIXELS"), because ListTile budgets the trailing height from the
    // title, not from the trailing content.
    final pill = StatusPill(label: label, color: color);

    return PortalCard(
      lift: false,
      accent: color,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: StatusTint.surface(context, color),
                child: Icon(Icons.badge, color: StatusTint.onTint(context, color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(worker.fullName, style: theme.textTheme.titleMedium),
                    Text(worker.workerCode, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    if (worker.vehiclePlate != null)
                      Text(
                        'Plate: ${worker.vehiclePlate}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              // Beside the name the pill is a non-flexible child of a Row and
              // is laid out unbounded, so on a phone it goes on its own line
              // where it can wrap instead.
              if (density.isWide) ...[const SizedBox(width: 8), pill],
            ],
          ),
          if (!density.isWide) ...[const SizedBox(height: 10), pill],
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton(
                onPressed: () => _showFileIncidentDialog(worker),
                child: const Text('File incident'),
              ),
              TextButton(
                onPressed: () => _showIncidentHistory(worker),
                child: const Text('Incident history'),
              ),
              TextButton(
                onPressed: () => _removeFromRoster(worker),
                style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
                child: const Text('Remove from roster'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
