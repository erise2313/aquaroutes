import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../models/permit.dart';
import '../../models/web_content.dart';
import '../../services/permit_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/portal/portal.dart';

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
  Map<PermitType, PermitTypeLabel> _labels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final station = await _supabase
          .from('water_stations')
          .select('id, is_accredited')
          .eq('owner_profile_id', userId)
          .maybeSingle();

      if (station == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final stationId = station['id'] as String;
      final permits = await _permitService.fetchStationPermits(stationId);
      final labels = await _permitService.fetchPermitLabels();

      if (mounted) {
        setState(() {
          _stationId = stationId;
          _isAccredited = station['is_accredited'] as bool? ?? false;
          _permits = permits.where((p) => p.isRequired).toList();
          _labels = {for (final l in labels) l.permitType: l};
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);

    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Governance & compliance',
            title: 'Permit Vault',
            subtitle: 'The documents the association reviews before accrediting your station',
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _stationId == null
                ? const PortalEmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No station linked to this account',
                    message: 'Your account is not linked to a water station, so there are no permits to manage.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: density.pagePadding,
                      children: [
                        _buildAccreditationCallout(),
                        SizedBox(height: density.sectionGap),
                        if (_permits.isEmpty)
                          const PortalEmptyState(
                            icon: Icons.folder_open_outlined,
                            title: 'No permits required yet',
                            message: 'Which permits you need depends on what your station sells. '
                                'List your products and the association will ask for the right ones.',
                          )
                        else
                          PortalSection(
                            title: 'Required permits',
                            subtitle: _permits.length == 1 ? '1 document' : '${_permits.length} documents',
                            child: Column(
                              children: [
                                for (var i = 0; i < _permits.length; i++)
                                  _buildPermitCard(_permits[i], last: i == _permits.length - 1, density: density),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Was a Card filled with green.shade50 / amber.shade50 -- a pale fill that
  /// stayed pale in dark mode, leaving light text on a near-white block.
  /// StatusCallout tints from the theme instead.
  Widget _buildAccreditationCallout() {
    if (_isAccredited) {
      return const StatusCallout(
        accent: AppColors.cleared,
        icon: Icons.verified,
        title: 'Fully accredited',
        message: 'All required permits have been approved by WASA.',
      );
    }

    return const StatusCallout(
      accent: AppColors.pendingClearance,
      icon: Icons.hourglass_top,
      title: 'Accreditation pending',
      message: 'Accreditation unlocks once every required permit below is approved.',
    );
  }

  Widget _buildPermitCard(Permit permit, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final label = _labels[permit.permitType]?.label ?? permit.permitType.name;

    final (statusColor, statusIcon, statusLabel) = switch (permit.status) {
      PermitStatus.approved => (AppColors.cleared, Icons.check_circle, 'APPROVED'),
      PermitStatus.pendingReview => (AppColors.pendingClearance, Icons.hourglass_top, 'PENDING REVIEW'),
      PermitStatus.rejected => (AppColors.flagged, Icons.cancel, 'REJECTED'),
      PermitStatus.missing => (AppColors.inkMuted, Icons.upload_file, 'NOT UPLOADED'),
    };

    return PortalCard(
      lift: false,
      accent: statusColor,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: StatusTint.surface(context, statusColor), shape: BoxShape.circle),
                child: Icon(statusIcon, color: StatusTint.onTint(context, statusColor), size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          // A Wrap bounds its children, so a long status label wraps rather
          // than running off the card at large system text.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(label: statusLabel, color: statusColor),
              if (permit.isRenewalDueSoon)
                const StatusPill(label: 'RENEWAL DUE', color: AppColors.pendingClearance),
            ],
          ),
          if (permit.status == PermitStatus.rejected && permit.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${permit.rejectionReason}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          PortalActionRow(
            children: [
              OutlinedButton.icon(
                onPressed: () => _upload(permit),
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(permit.status == PermitStatus.missing ? 'Upload document' : 'Replace document'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
