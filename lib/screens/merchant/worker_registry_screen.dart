import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/worker.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/confirm_dialog.dart';

/// Station-owner side of the Worker Security Registry: add workers and file
/// incidents (missing cash, lost jugs, etc). Filing an incident immediately
/// knocks the worker back to pending_clearance; only a WASA admin can
/// confirm it into 'flagged' or dismiss it (0005_workers.sql triggers) --
/// this screen deliberately has no way to flag a worker directly.
class WorkerRegistryScreen extends StatefulWidget {
  const WorkerRegistryScreen({super.key});

  @override
  State<WorkerRegistryScreen> createState() => _WorkerRegistryScreenState();
}

class _WorkerRegistryScreenState extends State<WorkerRegistryScreen> {
  final _workerService = WorkerService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;
  final _addWorkerFormKey = GlobalKey<FormState>();
  final _incidentFormKey = GlobalKey<FormState>();

  String? _stationId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveStation();
  }

  Future<void> _resolveStation() async {
    final userId = _supabase.auth.currentUser!.id;
    final station = await _supabase.from('water_stations').select('id').eq('owner_profile_id', userId).maybeSingle();
    if (mounted) {
      setState(() {
        _stationId = station?['id'] as String?;
        _isLoading = false;
      });
    }
  }

  void _showAddWorkerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final plateController = TextEditingController();
    final capacityController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Worker'),
        content: SingleChildScrollView(
          child: Form(
            key: _addWorkerFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required.' : null,
                ),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return RegExp(r'^[0-9+\-\s]{7,}$').hasMatch(v.trim()) ? null : 'Enter a valid phone number.';
                  },
                ),
                TextFormField(controller: plateController, decoration: const InputDecoration(labelText: 'Vehicle Plate')),
                TextFormField(
                  controller: capacityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Jug Capacity'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!_addWorkerFormKey.currentState!.validate()) return;
              await _workerService.addWorker(
                stationId: _stationId!,
                fullName: nameController.text.trim(),
                phoneNumber: phoneController.text.trim(),
                vehiclePlate: plateController.text.trim(),
                jugCapacity: int.tryParse(capacityController.text.trim()),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFromRoster(Worker worker) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove from Roster',
      message: 'Remove ${worker.fullName} from your station? Their clearance/incident history is preserved -- they can be re-linked by a station anytime.',
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                await _workerService.fileIncident(
                  workerId: worker.id,
                  reportedByProfileId: _supabase.auth.currentUser!.id,
                  incidentType: incidentType,
                  description: descriptionController.text.trim(),
                  amountInvolved: double.tryParse(amountController.text.trim()),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Submit to WASA', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showIncidentHistory(Worker worker) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<List<WorkerIncident>>(
          future: _workerService.fetchIncidentsForWorker(worker.id),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final incidents = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Incident History: ${worker.fullName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: incidents.isEmpty
                        ? const Center(child: Text('No incidents filed against this worker.', style: TextStyle(color: Colors.grey)))
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(incident.incidentType, style: const TextStyle(fontWeight: FontWeight.bold))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(incident.description),
            if (incident.amountInvolved != null) Text('Amount involved: ${formatPeso(incident.amountInvolved!)}'),
            const SizedBox(height: 4),
            Text(
              'Filed ${DateFormat('MMM d, yyyy').format(incident.createdAt)}'
              '${incident.resolvedAt != null ? ' · Resolved ${DateFormat('MMM d, yyyy').format(incident.resolvedAt!)}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker Registry'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add), onPressed: _stationId == null ? null : _showAddWorkerDialog),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stationId == null
              ? const Center(child: Text('No station linked to this account.'))
              : StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _workerService.watchStationWorkers(_stationId!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final workers = snapshot.data!.map((m) => Worker.fromMap(m)).toList();
                    if (workers.isEmpty) {
                      return const Center(child: Text('No workers registered yet.'));
                    }
                    return ListView.builder(
                      itemCount: workers.length,
                      itemBuilder: (context, index) => _buildWorkerCard(workers[index]),
                    );
                  },
                ),
    );
  }

  Widget _buildWorkerCard(Worker worker) {
    final (color, label) = switch (worker.clearanceStatus) {
      ClearanceStatus.cleared => (AppColors.cleared, 'CLEARED'),
      ClearanceStatus.pendingClearance => (AppColors.pendingClearance, 'PENDING'),
      ClearanceStatus.flagged => (AppColors.flagged, 'FLAGGED'),
    };

    // A plain ListTile with a trailing Column doesn't work once there are
    // 3+ stacked items (status badge + File Incident + Incident History +
    // Remove from Roster) -- ListTile gives trailing a fixed height budget
    // based on the title/subtitle content, not the trailing content, so it
    // silently overflowed ("BOTTOM OVERFLOWED BY 108 PIXELS") once
    // Incident History was added as a third button. A header row + a Wrap
    // footer (which wraps to a new line instead of overflowing) fixes this
    // regardless of how many actions end up here later.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(Icons.badge, color: color)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(worker.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(worker.workerCode, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      if (worker.vehiclePlate != null)
                        Text('Plate: ${worker.vehiclePlate}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _showFileIncidentDialog(worker),
                  child: const Text('File Incident', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _showIncidentHistory(worker),
                  child: const Text('Incident History', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _removeFromRoster(worker),
                  child: const Text('Remove from Roster', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
