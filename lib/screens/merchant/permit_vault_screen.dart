import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/permit.dart';
import '../../services/permit_service.dart';
import '../../services/supabase_service.dart';

/// Multi-document permit upload for a station. Which permits show up as
/// required is entirely server-driven (a Postgres trigger on
/// water_stations.offered_water_types toggles alkaline_tech_cert/
/// alkaline_water_test) -- this screen just renders whatever `permits` rows
/// exist for the station, so the alkaline conditional logic lives in one
/// place (the DB), not duplicated in client code.
class PermitVaultScreen extends StatefulWidget {
  const PermitVaultScreen({super.key});

  @override
  State<PermitVaultScreen> createState() => _PermitVaultScreenState();
}

class _PermitVaultScreenState extends State<PermitVaultScreen> {
  final _permitService = PermitService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _stationId;
  bool _isAccredited = false;
  List<Permit> _permits = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final station = await _supabase
          .from('water_stations')
          .select('id, is_accredited')
          .eq('owner_profile_id', userId)
          .maybeSingle();

      if (station == null) {
        setState(() => _isLoading = false);
        return;
      }

      final stationId = station['id'] as String;
      final permits = await _permitService.fetchStationPermits(stationId);

      if (mounted) {
        setState(() {
          _stationId = stationId;
          _isAccredited = station['is_accredited'] as bool? ?? false;
          _permits = permits.where((p) => p.isRequired).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _upload(Permit permit) async {
    // withData: true returns raw bytes on every platform (not just web) --
    // PermitService takes bytes now, not a dart:io File, since File doesn't
    // exist on Flutter web at all.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;

    final extension = picked.extension ?? 'pdf';

    try {
      await _permitService.uploadPermitDocument(
        stationId: _stationId!,
        permitType: permit.permitType,
        bytes: picked.bytes!,
        fileExtension: extension,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded -- pending WASA review.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permit Vault')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stationId == null
              ? const Center(child: Text('No station linked to this account.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: _isAccredited ? Colors.green.shade50 : Colors.amber.shade50,
                      child: ListTile(
                        leading: Icon(
                          _isAccredited ? Icons.verified : Icons.hourglass_top,
                          color: _isAccredited ? Colors.green : Colors.amber.shade800,
                        ),
                        title: Text(_isAccredited ? 'Fully Accredited' : 'Accreditation Pending'),
                        subtitle: Text(
                          _isAccredited
                              ? 'All required permits have been approved by WASA.'
                              : 'Accreditation unlocks once every required permit below is approved.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._permits.map(_buildPermitCard),
                  ],
                ),
    );
  }

  Widget _buildPermitCard(Permit permit) {
    final label = _permitLabel(permit.permitType);
    final (statusColor, statusIcon, statusLabel) = switch (permit.status) {
      PermitStatus.approved => (Colors.green, Icons.check_circle, 'Approved'),
      PermitStatus.pendingReview => (Colors.orange, Icons.hourglass_top, 'Pending Review'),
      PermitStatus.rejected => (Colors.red, Icons.cancel, 'Rejected'),
      PermitStatus.missing => (Colors.grey, Icons.upload_file, 'Not Uploaded'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(statusLabel, style: TextStyle(color: statusColor)),
            if (permit.status == PermitStatus.rejected && permit.rejectionReason != null)
              Text('Reason: ${permit.rejectionReason}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: TextButton(
          onPressed: () => _upload(permit),
          child: Text(permit.status == PermitStatus.missing ? 'Upload' : 'Re-upload'),
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
