import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../services/worker_credential_service.dart';
import '../../widgets/confirm_dialog.dart';

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
  const WorkerClearanceScreen({super.key});

  @override
  State<WorkerClearanceScreen> createState() => _WorkerClearanceScreenState();
}

class _WorkerClearanceScreenState extends State<WorkerClearanceScreen> {
  final _supabase = Supabase.instance.client;
  final _credentialService = WorkerCredentialService(SupabaseService.instance);

  bool _isLoading = true;
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _credentials = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() => _isLoading = true);
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

    await _supabase.from('worker_incidents').update({
      'status': confirmFlag ? 'confirmed_flag' : 'dismissed',
      'resolved_by': _supabase.auth.currentUser!.id,
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);
    await _fetchAll();
  }

  Future<void> _reviewCredential(String credentialId, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await _promptRejectionReason();
      if (reason == null) return;
    }
    await _credentialService.reviewCredential(
      credentialId: credentialId,
      approve: approve,
      reviewedByProfileId: _supabase.auth.currentUser!.id,
      rejectionReason: reason,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open document: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Worker Clearance Review'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Incidents (${_incidents.length})'),
              Tab(text: 'Credentials (${_credentials.length})'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _incidents.isEmpty
                      ? const Center(child: Text('No incidents awaiting review.'))
                      : RefreshIndicator(
                          onRefresh: _fetchAll,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _incidents.length,
                            itemBuilder: (context, index) => _buildIncidentCard(_incidents[index]),
                          ),
                        ),
                  _credentials.isEmpty
                      ? const Center(child: Text('No credentials awaiting review.'))
                      : RefreshIndicator(
                          onRefresh: _fetchAll,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _credentials.length,
                            itemBuilder: (context, index) => _buildCredentialCard(_credentials[index]),
                          ),
                        ),
                ],
              ),
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> incident) {
    final worker = incident['workers'] as Map<String, dynamic>?;
    final station = worker?['water_stations'] as Map<String, dynamic>?;
    final amount = incident['amount_involved'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(worker?['full_name'] ?? 'Unknown Worker', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${worker?['worker_code'] ?? ''} · ${station?['station_name'] ?? 'Unknown Station'}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text('Type: ${incident['incident_type']}'),
            if (amount != null) Text('Amount involved: ₱$amount'),
            const SizedBox(height: 4),
            Text(incident['description'] ?? ''),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolveIncident(incident['id'] as String, false),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.flagged),
                    onPressed: () => _resolveIncident(incident['id'] as String, true),
                    child: const Text('Confirm Flag', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialCard(Map<String, dynamic> credential) {
    final worker = credential['workers'] as Map<String, dynamic>?;
    final label = credential['credential_type'] == 'drivers_license' ? "Driver's License" : 'Government-Issued ID';
    final storagePath = credential['storage_path'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(worker?['full_name'] ?? 'Unknown Worker', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(worker?['worker_code'] ?? '', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Row(
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reviewCredential(credential['id'] as String, false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cleared),
                    onPressed: () => _reviewCredential(credential['id'] as String, true),
                    child: const Text('Approve', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
