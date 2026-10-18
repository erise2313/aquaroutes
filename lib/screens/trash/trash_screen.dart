import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/trash_note.dart';

/// "Removed for good in 3 days", "... tomorrow", "... today". Pure, so it
/// is unit-tested.
String trashCountdown(DateTime purgeAfter, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(purgeAfter.year, purgeAfter.month, purgeAfter.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days <= 0) return 'Removed for good today';
  if (days == 1) return 'Removed for good tomorrow';
  return 'Removed for good in $days days';
}

/// Deleted things, kept $trashRetentionDays days (patch_trash.sql). Each
/// person sees what they deleted; officers see everything. Restore puts an
/// item back exactly as it was -- a post with its comments and reactions;
/// "Delete for good" doesn't wait for the daily job.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, this.embedded = false, this.isOfficer = false});

  /// In the admin portal's sidebar: the shell supplies the frame, so no
  /// AppBar of its own.
  final bool embedded;

  /// Officers also see who deleted each item, and clear the files of items
  /// removed for good.
  final bool isOfficer;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String? _busyId;

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
      final rows = await _supabase
          .from('trash')
          .select('id, kind, label, deleted_at, purge_after, deleted_by, profiles!trash_deleted_by_fkey(full_name)')
          .eq('is_child', false)
          .order('deleted_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
      });
      if (widget.isOfficer) _clearPurgedFiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the Trash. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  /// Files of items removed for good wait in storage_cleanup -- the database
  /// can't delete storage files itself. Best-effort; retried next time.
  Future<void> _clearPurgedFiles() async {
    try {
      final queued = await _supabase.from('storage_cleanup').select('id, bucket, path').limit(100);
      for (final q in queued) {
        await _supabase.storage.from(q['bucket'] as String).remove([q['path'] as String]);
        await _supabase.from('storage_cleanup').delete().eq('id', q['id'] as String);
      }
    } catch (_) {}
  }

  String _friendly(Object e) {
    final text = describeError(e);
    // Before patch_trash_part2.sql has been run in the SQL Editor.
    if (text.contains('restore_from_trash') || text.contains('purge_trash_item') || text.contains('PGRST202')) {
      return 'Restoring isn\'t switched on yet -- the last database step still needs running.';
    }
    return text;
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    setState(() => _busyId = item['id'] as String);
    try {
      await _supabase.rpc('restore_from_trash', params: {'p_trash_id': item['id']});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item['kind']} restored.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _purge(Map<String, dynamic> item) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete for good?',
      message: 'This ${(item['kind'] as String).toLowerCase()} can\'t be restored after this.',
      confirmLabel: 'Delete for good',
      isDestructive: true,
    );
    if (!ok) return;
    setState(() => _busyId = item['id'] as String);
    try {
      await _supabase.rpc('purge_trash_item', params: {'p_trash_id': item['id']});
      if (widget.isOfficer) await _clearPurgedFiles();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.embedded)
          const AdminPageHeader(
            eyebrow: 'People',
            title: 'Trash',
            subtitle: 'Everything deleted in the last $trashRetentionDays days, by anyone. Restore it, or delete it for good.',
          ),
        Expanded(child: _buildBody()),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Trash')), body: body);
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 48),
            PortalEmptyState(
              icon: Icons.delete_outline,
              title: 'Trash is empty',
              message: 'Anything you delete waits here for $trashRetentionDays days, so you can bring it back.',
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final fmt = DateFormat('MMM d, h:mm a');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: PortalDensity.of(context).pagePadding,
        children: [
          if (!widget.embedded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'What you deleted in the last $trashRetentionDays days. After that it\'s removed for good.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final item in _items)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['kind'] as String, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(
                    (item['label'] as String?)?.trim().isNotEmpty == true ? item['label'] as String : '(no title)',
                    style: theme.textTheme.titleMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'Deleted ${fmt.format(DateTime.parse(item['deleted_at'] as String).toLocal())}',
                      if (widget.isOfficer && item['profiles']?['full_name'] != null) 'by ${item['profiles']['full_name']}',
                      trashCountdown(DateTime.parse(item['purge_after'] as String).toLocal()),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _busyId == null ? () => _restore(item) : null,
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                      ),
                      TextButton.icon(
                        onPressed: _busyId == null ? () => _purge(item) : null,
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Delete for good'),
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
}
