import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/error_text.dart';
import '../../widgets/confirm_dialog.dart';

/// Earlier versions of one website page's content, newest first, each with
/// a Restore button (web_content_revisions, supabase/patch_overhaul_gaps.sql).
///
/// Every save used to overwrite the previous text for good. Now each edit or
/// delete keeps what was there before, and restoring is itself an edit -- so
/// a restore can be undone too.
///
/// [pageKey] is the page's key in web_page_sections / web_content_items, or
/// null for the FAQ, whose entries have no page key.
///
/// Returns true if something was restored, so the editor can reload.
Future<bool> showWebsiteContentHistory(BuildContext context, {required String title, String? pageKey}) async {
  final restored = await showDialog<bool>(
    context: context,
    builder: (_) => _HistoryDialog(title: title, pageKey: pageKey),
  );
  return restored ?? false;
}

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.title, required this.pageKey});

  final String title;
  final String? pageKey;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

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
      var query = _supabase
          .from('web_content_revisions')
          .select('id, table_name, snapshot, changed_at, profiles(full_name)');
      query = widget.pageKey == null
          ? query.eq('table_name', 'web_faq_entries')
          : query.eq('snapshot->>page_key', widget.pageKey!);
      final rows = await query.order('changed_at', ascending: false).limit(50);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the history. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Restore this version?',
      message: 'The website will show this text again. What is there now is kept in the history, so you can undo this.',
      confirmLabel: 'Restore',
      isDestructive: false,
    );
    if (!ok || !mounted) return;
    try {
      await _supabase.rpc('restore_web_content_revision', params: {'p_revision_id': row['id']});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  String _preview(Map<String, dynamic> snapshot) {
    final parts = [
      snapshot['title'],
      snapshot['question'],
      snapshot['body'],
      snapshot['answer'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty);
    return parts.join(' -- ');
  }

  String _what(Map<String, dynamic> row) {
    final s = row['snapshot'] as Map<String, dynamic>;
    return switch (row['table_name']) {
      'web_page_sections' => 'Section: ${(s['section_key'] as String? ?? '').replaceAll('_', ' ')}',
      'web_content_items' => 'Item in ${(s['item_key'] as String? ?? '').replaceAll('_', ' ')}',
      'web_faq_entries' => 'FAQ entry',
      _ => 'Content',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('History: ${widget.title}'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _rows.isEmpty
                    ? Center(
                        child: Text(
                          'No earlier versions yet. Each time this page is saved, the version it replaces is kept here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final row = _rows[i];
                          final who = (row['profiles'] as Map?)?['full_name'] ?? 'someone';
                          final when = DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(row['changed_at'] as String).toLocal());
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            title: Text(_what(row)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Replaced $when by $who', style: theme.textTheme.bodySmall),
                                const SizedBox(height: 4),
                                Text(_preview(row['snapshot'] as Map<String, dynamic>), maxLines: 3, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                            trailing: TextButton(onPressed: () => _restore(row), child: const Text('Restore')),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
      ],
    );
  }
}
