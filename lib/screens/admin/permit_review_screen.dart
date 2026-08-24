import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/permit.dart';
import '../../services/permit_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';

/// wasa_admin review of a single station's permit vault. Approving every
/// required permit flips water_stations.is_accredited automatically via the
/// recompute_accreditation() trigger (0004_permits.sql) -- this screen never
/// sets is_accredited itself. Toggling "colorum verification" (the public
/// map seal) is a separate, manual admin action.
class PermitReviewScreen extends StatefulWidget {
  const PermitReviewScreen({super.key, required this.stationId, required this.stationName});

  final String stationId;
  final String stationName;

  @override
  State<PermitReviewScreen> createState() => _PermitReviewScreenState();
}

class _PermitReviewScreenState extends State<PermitReviewScreen> {
  final _permitService = PermitService(SupabaseService.instance);
  final _stationService = StationService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Permit> _permits = [];
  bool _isColorumVerified = false;
  bool _isAccredited = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final permits = await _permitService.fetchStationPermits(widget.stationId);
    final station = await _supabase
        .from('water_stations')
        .select('is_colorum_verified, is_accredited')
        .eq('id', widget.stationId)
        .single();

    if (mounted) {
      setState(() {
        _permits = permits.where((p) => p.isRequired).toList();
        _isColorumVerified = station['is_colorum_verified'] as bool? ?? false;
        _isAccredited = station['is_accredited'] as bool? ?? false;
        _isLoading = false;
      });
    }
  }

  Future<void> _review(Permit permit, bool approve) async {
    if (!approve) {
      final reason = await _promptRejectionReason();
      if (reason == null) return;
      await _permitService.reviewPermit(
        permitId: permit.id,
        approve: false,
        reviewedByProfileId: _supabase.auth.currentUser!.id,
        rejectionReason: reason,
      );
    } else {
      final expiryDate = await _promptExpiryDate();
      await _permitService.reviewPermit(
        permitId: permit.id,
        approve: true,
        reviewedByProfileId: _supabase.auth.currentUser!.id,
        expiryDate: expiryDate,
      );
    }
    await _load();
  }

  /// Optional -- not every permit type has a hard renewal date, so the
  /// admin may dismiss this without picking one.
  Future<DateTime?> _promptExpiryDate() async {
    final setExpiry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Renewal Date?'),
        content: const Text('Optionally set an expiry date to get a renewal reminder before it lapses.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Skip')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set Date')),
        ],
      ),
    );
    if (setExpiry != true || !mounted) return null;

    return showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
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

  Future<void> _viewDocument(Permit permit) async {
    if (permit.storagePath == null) return;
    try {
      final url = await _permitService.getSignedUrl(permit.storagePath!);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open document: $e')));
      }
    }
  }

  Future<void> _toggleColorumVerified(bool value) async {
    await _stationService.updateStation(widget.stationId, {'is_colorum_verified': value});
    setState(() => _isColorumVerified = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.stationName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: _isAccredited ? Colors.green.shade50 : Colors.grey.shade100,
                  child: ListTile(
                    leading: Icon(_isAccredited ? Icons.verified : Icons.hourglass_top, color: _isAccredited ? Colors.green : Colors.grey),
                    title: Text(_isAccredited ? 'Accredited' : 'Not yet accredited'),
                    subtitle: const Text('Flips automatically once every required permit below is approved.'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: const Text('Colorum Verification Seal'),
                    subtitle: const Text('Marks this station as a legitimate, licensed operator on the public map.'),
                    value: _isColorumVerified,
                    onChanged: _toggleColorumVerified,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Permits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._permits.map(_buildPermitTile),
              ],
            ),
    );
  }

  Widget _buildPermitTile(Permit permit) {
    final (statusColor, statusLabel) = switch (permit.status) {
      PermitStatus.approved => (Colors.green, 'Approved'),
      PermitStatus.pendingReview => (Colors.orange, 'Pending Review'),
      PermitStatus.rejected => (Colors.red, 'Rejected'),
      PermitStatus.missing => (Colors.grey, 'Not Uploaded'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(_permitLabel(permit.permitType))),
            if (permit.isRenewalDueSoon) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
                child: const Text('Renewal due', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        subtitle: Text(statusLabel, style: TextStyle(color: statusColor)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (permit.storagePath != null)
              IconButton(
                icon: const Icon(Icons.visibility_outlined, color: Colors.blueGrey),
                tooltip: 'View Document',
                onPressed: () => _viewDocument(permit),
              ),
            if (permit.status == PermitStatus.pendingReview) ...[
              IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () => _review(permit, true)),
              IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => _review(permit, false)),
            ],
          ],
        ),
      ),
    );
  }

  String _permitLabel(PermitType type) {
    switch (type) {
      case PermitType.businessPermit:
        return "Mayor's Business Permit";
      case PermitType.sanitaryPermit:
        return 'Sanitary Permit';
      case PermitType.fdaLicense:
        return 'FDA License to Operate';
      case PermitType.alkalineTechCert:
        return 'Alkaline Machine Technical Certification';
      case PermitType.alkalineWaterTest:
        return 'Alkaline Water Quality Test Report';
    }
  }
}
