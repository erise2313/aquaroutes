import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/permit.dart';
import '../../models/web_content.dart';
import '../../services/permit_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../constants/app_colors.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';

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
  String? _error;
  List<Permit> _permits = [];
  bool _isColorumVerified = false;
  bool _isAccredited = false;
  bool _isAccreditationOverridden = false;
  String? _overriddenByName;
  DateTime? _overriddenAt;
  Map<PermitType, PermitTypeLabel> _labels = {};

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
      final permits = await _permitService.fetchStationPermits(widget.stationId);
      final labels = await _permitService.fetchPermitLabels();
      final station = await _supabase
          .from('water_stations')
          .select('is_colorum_verified, is_accredited, accreditation_override_by, accreditation_override_at')
          .eq('id', widget.stationId)
          .single();

      final overriddenByProfileId = station['accreditation_override_by'] as String?;
      String? overriddenByName;
      if (overriddenByProfileId != null) {
        final overriddenByProfile = await _supabase
            .from('profiles')
            .select('full_name')
            .eq('id', overriddenByProfileId)
            .maybeSingle();
        overriddenByName = overriddenByProfile?['full_name'] as String?;
      }

      if (mounted) {
        setState(() {
          // Shows every permit, not just the currently-required ones --
          // an admin who toggles one off (e.g. NWRB items for a station on
          // public water supply) needs to still see it here to toggle it
          // back on later, not have it vanish permanently.
          _permits = [...permits]..sort((a, b) => (b.isRequired ? 1 : 0) - (a.isRequired ? 1 : 0));
          _labels = {for (final l in labels) l.permitType: l};
          _isColorumVerified = station['is_colorum_verified'] as bool? ?? false;
          _isAccredited = station['is_accredited'] as bool? ?? false;
          _isAccreditationOverridden = overriddenByProfileId != null;
          _overriddenByName = overriddenByName;
          _overriddenAt = station['accreditation_override_at'] == null
              ? null
              : DateTime.parse(station['accreditation_override_at'] as String);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this station\'s permits. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _review(Permit permit, bool approve) async {
    try {
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
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not review permit. ${describeError(e)}')));
    }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open document. ${describeError(e)}')));
      }
    }
  }

  Future<void> _toggleAccreditationOverride(bool value) async {
    if (value) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Manually Certify This Station?',
        message: 'This will mark ${widget.stationName} as accredited regardless of missing or rejected required permits, '
            'and it will stay accredited even if a permit later expires or is rejected -- until you turn this off again.',
        confirmLabel: 'Certify Anyway',
      );
      if (!confirmed) return;
    }

    try {
      await _permitService.setAccreditationOverride(widget.stationId, value);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update accreditation override. ${describeError(e)}')));
      }
    }
  }

  Future<void> _toggleColorumVerified(bool value) async {
    try {
      await _stationService.updateStation(widget.stationId, {'is_colorum_verified': value});
      if (mounted) setState(() => _isColorumVerified = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update verification. ${describeError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // An in-body header rather than an AppBar: this was the one admin screen
      // still stacking a page AppBar under the nav shell's, which is exactly
      // the two-navy-bars problem AdminPageHeader exists to prevent. Pushed
      // from Station Accreditation, so it gets a back button automatically.
      body: Column(
        children: [
          AdminPageHeader(
            eyebrow: 'Station review',
            title: widget.stationName,
            subtitle: 'Permits, accreditation, and the public verification seal',
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Was a Card filled with green.shade50 or grey.shade100:
                      // a pale block that stayed pale in dark mode.
                      StatusCallout(
                        accent: _isAccredited ? AppColors.cleared : AppColors.inkMuted,
                        icon: _isAccredited ? Icons.verified : Icons.hourglass_top,
                        title: _isAccredited ? 'Accredited' : 'Not yet accredited',
                        message: _isAccreditationOverridden
                            ? 'Manually certified by ${_overriddenByName ?? 'a WASA admin'}'
                                '${_overriddenAt != null ? ' on ${DateFormat('MMM d, yyyy \'at\' h:mm a').format(_overriddenAt!)}' : ''} '
                                '-- won\'t change automatically until the override below is cleared.'
                            : 'Flips automatically once every required permit below is approved.',
                      ),
                      const SizedBox(height: 10),
                      PortalCard(
                        lift: false,
                        padding: EdgeInsets.zero,
                        accent: _isAccreditationOverridden ? AppColors.pendingClearance : null,
                        child: SwitchListTile(
                          title: const Text('Manually certify (override)'),
                          subtitle: Text(
                            'Accredit this station even with missing or rejected required permits. '
                            'A future permit change won\'t undo this until you turn it back off.',
                            style: theme.textTheme.bodySmall,
                          ),
                          value: _isAccreditationOverridden,
                          onChanged: _toggleAccreditationOverride,
                        ),
                      ),
                      const SizedBox(height: 10),
                      PortalCard(
                        lift: false,
                        padding: EdgeInsets.zero,
                        child: SwitchListTile(
                          title: const Text('Colorum verification seal'),
                          subtitle: Text(
                            'Marks this station as a legitimate, licensed operator on the public map.',
                            style: theme.textTheme.bodySmall,
                          ),
                          value: _isColorumVerified,
                          onChanged: _toggleColorumVerified,
                        ),
                      ),
                      const SizedBox(height: 28),
                      PortalSection(
                        title: 'Permits',
                        subtitle: 'Every permit for this station, including ones not required here',
                        child: Column(children: _permits.map(_buildPermitTile).toList()),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _setRequired(Permit permit, bool value) async {
    try {
      await _permitService.setRequired(permit.id, value);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update. ${describeError(e)}')));
    }
  }

  Widget _buildPermitTile(Permit permit) {
    final theme = Theme.of(context);

    final (statusColor, statusLabel) = switch (permit.status) {
      PermitStatus.approved => (AppColors.cleared, 'APPROVED'),
      PermitStatus.pendingReview => (AppColors.pendingClearance, 'PENDING REVIEW'),
      PermitStatus.rejected => (AppColors.flagged, 'REJECTED'),
      PermitStatus.missing => (AppColors.inkMuted, 'NOT UPLOADED'),
    };

    final isPending = permit.isRequired && permit.status == PermitStatus.pendingReview;

    return Opacity(
      opacity: permit.isRequired ? 1.0 : 0.55,
      child: PortalCard(
        lift: false,
        accent: permit.isRequired ? statusColor : AppColors.inkMuted,
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _labels[permit.permitType]?.label ?? permit.permitType.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Required for this station',
                  child: Switch(value: permit.isRequired, onChanged: (v) => _setRequired(permit, v)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (permit.isRequired)
                  AdminStatusPill(label: statusLabel, color: statusColor)
                else
                  const AdminStatusPill(label: 'NOT REQUIRED HERE', color: AppColors.inkMuted),
                if (permit.isRenewalDueSoon)
                  const AdminStatusPill(label: 'RENEWAL DUE', color: AppColors.pendingClearance),
              ],
            ),
            if (permit.storagePath != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _viewDocument(permit),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View document'),
                ),
              ),
            ],
            // Approve/Reject are labeled buttons, not bare icons -- these are
            // consequential, permanent decisions, and a green check next to a
            // red X says nothing on its own. Matches worker_clearance_screen,
            // so one action looks the same in both places.
            if (isPending) ...[
              const SizedBox(height: 10),
              PortalActionRow(
                children: [
                  OutlinedButton(
                    onPressed: () => _review(permit, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.flagged,
                      side: const BorderSide(color: AppColors.flagged),
                    ),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.cleared),
                    onPressed: () => _review(permit, true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
