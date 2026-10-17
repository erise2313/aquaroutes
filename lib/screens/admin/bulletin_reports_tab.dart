import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../services/bulletin_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';

/// Posts members have reported, grouped by post, for an officer to act on:
/// hide the post (it leaves every feed but is kept for the record) or
/// decide it's fine. Either way the reports on it are closed.
class BulletinReportsTab extends StatefulWidget {
  const BulletinReportsTab({super.key, this.onChanged});

  /// Called after an action, so the host can refresh its badge.
  final VoidCallback? onChanged;

  @override
  State<BulletinReportsTab> createState() => _BulletinReportsTabState();
}

class _BulletinReportsTabState extends State<BulletinReportsTab> {
  final _service = BulletinService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;

  /// Open reports grouped by the post they're about.
  Map<String, List<Map<String, dynamic>>> _byPost = {};

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
      final reports = await _service.fetchOpenReports();
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final r in reports) {
        grouped.putIfAbsent(r['bulletin_id'] as String, () => []).add(r);
      }
      if (mounted) {
        setState(() {
          _byPost = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load reports. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _act(String bulletinId, {required bool hide}) async {
    try {
      if (hide) await _service.setHidden(bulletinId, true);
      await _service.resolveReports(bulletinId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hide ? 'Post hidden and reports closed.' : 'Reports closed; the post stays up.'),
        ));
      }
      widget.onChanged?.call();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 3));
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_byPost.isEmpty)
            const PortalEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No reported posts',
              message: 'When a member reports a bulletin post, it appears here for you to hide or keep.',
            )
          else
            for (final entry in _byPost.entries)
              Builder(builder: (context) {
                final reports = entry.value;
                final post = reports.first['bulletins'] as Map<String, dynamic>?;
                final hidden = post?['is_hidden'] == true;
                return PortalCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  accent: AppColors.flagged,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(post?['title'] as String? ?? 'Deleted post', style: theme.textTheme.titleMedium),
                          ),
                          StatusPill(
                            label: '${reports.length} report${reports.length == 1 ? '' : 's'}',
                            color: AppColors.flagged,
                            icon: Icons.flag_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Posted by ${post?['author_name'] ?? 'unknown'}', style: theme.textTheme.bodySmall),
                      if (post?['body'] != null) ...[
                        const SizedBox(height: 8),
                        Text(post!['body'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 12),
                      for (final r in reports)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.format_quote, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${r['reason']} -- ${(r['profiles'] as Map?)?['full_name'] ?? 'a member'}, '
                                  '${DateFormat('MMM d').format(DateTime.parse(r['created_at'] as String).toLocal())}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      PortalActionRow(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _act(entry.key, hide: false),
                            icon: const Icon(Icons.check),
                            label: const Text('Keep the post'),
                          ),
                          FilledButton.icon(
                            onPressed: hidden ? null : () => _act(entry.key, hide: true),
                            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                            icon: const Icon(Icons.visibility_off_outlined),
                            label: Text(hidden ? 'Already hidden' : 'Hide the post'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
        ],
      ),
    );
  }
}
