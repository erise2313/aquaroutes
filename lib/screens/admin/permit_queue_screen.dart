import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/brand_tokens.dart';
import '../../models/permit.dart';
import '../../services/permit_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import 'admin_route.dart';
import '../../widgets/portal/fill_grid.dart';
import 'permit_review_screen.dart';

/// Every permit waiting for an officer, across all stations, oldest first.
///
/// Before this screen an officer could only review permits by first finding
/// the station (Stations, then a station, then its permits) or by spotting
/// the item in the Overview's mixed queue. Reviewing is the portal's main
/// job, so it gets its own page in the sidebar.
class PermitQueueScreen extends StatefulWidget {
  const PermitQueueScreen({super.key});

  @override
  State<PermitQueueScreen> createState() => _PermitQueueScreenState();
}

class _PermitQueueScreenState extends State<PermitQueueScreen> {
  final _permitService = PermitService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<({Permit permit, String stationId, String stationName})> _queue = [];
  Map<PermitType, String> _labels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _permitService.fetchReviewQueue(),
        _permitService.fetchPermitLabels(),
      ]);
      if (!mounted) return;
      setState(() {
        _queue = results[0] as List<({Permit permit, String stationId, String stationName})>;
        _labels = {for (final l in results[1] as List) l.permitType as PermitType: l.label as String};
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the review queue. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  String _labelFor(PermitType type) => _labels[type] ?? permitTypeToString(type).replaceAll('_', ' ');

  Future<void> _open(String stationId, String stationName) async {
    await Navigator.push(context, adminRoute(PermitReviewScreen(stationId: stationId, stationName: stationName)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final stations = {for (final q in _queue) q.stationId}.length;

    return Scaffold(
      body: Column(
        children: [
          AdminPageHeader(
            eyebrow: 'Compliance',
            title: 'Permits',
            subtitle: 'Documents stations have uploaded and are waiting for you to approve or reject',
            actions: [
              IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            FillGrid(
                              maxColumns: 2,
                              children: [
                                PortalStatTile(
                                  value: _queue.length,
                                  label: 'Waiting for review',
                                  icon: Icons.pending_actions_outlined,
                                ),
                                PortalStatTile(
                                  value: stations,
                                  label: 'Stations affected',
                                  icon: Icons.store_mall_directory_outlined,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_queue.isEmpty)
                              const PortalEmptyState(
                                icon: Icons.task_alt,
                                title: 'Nothing to review',
                                message: 'When a station uploads a permit it appears here, oldest first. '
                                    'You can still see every station\'s permits under Stations.',
                              )
                            else
                              for (final q in _queue) _QueueRow(
                                label: _labelFor(q.permit.permitType),
                                stationName: q.stationName,
                                uploadedAt: q.permit.uploadedAt,
                                onReview: () => _open(q.stationId, q.stationName),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.label,
    required this.stationName,
    required this.uploadedAt,
    required this.onReview,
  });

  final String label;
  final String stationName;
  final DateTime? uploadedAt;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waited = uploadedAt == null ? null : DateTime.now().difference(uploadedAt!).inDays;

    return PortalCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onReview,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(stationName, style: theme.textTheme.bodyMedium),
              if (uploadedAt != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Uploaded ${DateFormat('MMM d, yyyy').format(uploadedAt!)}'
                  '${waited != null && waited > 0 ? ' · waiting $waited day${waited == 1 ? '' : 's'}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          );
          final button = FilledButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review'),
          );
          const pill = StatusPill(label: 'Awaiting review', color: BrandStatus.warning, icon: Icons.schedule);

          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 10), pill, const SizedBox(height: 10), button],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              pill,
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }
}
