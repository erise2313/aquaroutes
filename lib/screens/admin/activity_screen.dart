import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_theme.dart';
import '../../constants/app_colors.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/error_text.dart';
import '../../utils/csv_download.dart';
import '../../utils/csv_export.dart';
import '../../constants/admin_palette.dart';

/// Narrows activity rows by free-text search over who/what, plus category.
/// Top-level and pure so the matching rules are unit-testable.
List<Map<String, dynamic>> filterActivity(
  List<Map<String, dynamic>> rows, {
  String query = '',
  String? category,
}) {
  final q = query.trim().toLowerCase();
  return rows.where((row) {
    if (category != null && row['category'] != category) return false;
    if (q.isEmpty) return true;
    final actor = (row['actor_name'] as String?)?.toLowerCase() ?? '';
    final subject = (row['subject'] as String?)?.toLowerCase() ?? '';
    final action = (row['action'] as String?)?.toLowerCase() ?? '';
    return actor.contains(q) || subject.contains(q) || action.contains(q);
  }).toList();
}

/// "Who did what" across the portal, read from the `admin_activity` view
/// (supabase/patch_admin_activity_view.sql).
///
/// The actor columns behind this were already being written on nearly every
/// admin mutation, but only one was ever read back, so questions like "who
/// suspended this account?" had no answer anywhere in the UI.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  /// The feed is for "what happened recently", not forensics -- bounded so
  /// the screen can't be the one place in the portal that fetches unbounded.
  static const _limit = 200;

  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('admin_activity')
          .select()
          .order('occurred_at', ascending: false)
          .limit(_limit);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load activity. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  static const _categoryColors = {
    'Permit': AdminTheme.harborBlue,
    'Worker credential': AppColors.cleared,
    'Worker incident': AppColors.flagged,
    'Accreditation': AdminTheme.sealGold,
    'Website content': Color(0xFF0B4F5C),
  };

  static const _categoryIcons = {
    'Permit': Icons.description_outlined,
    'Worker credential': Icons.badge_outlined,
    'Worker incident': Icons.warning_amber_rounded,
    'Accreditation': Icons.verified_outlined,
    'Website content': Icons.web_outlined,
  };

  /// The audit trail, exportable for the association's records. Exports
  /// what's on screen, filters included.
  void _exportCsv() {
    final visible = filterActivity(_rows, query: _query, category: _category);
    final csv = buildCsv(
      const ['When', 'Who', 'Category', 'Action', 'Subject'],
      visible.map((row) {
        final occurred = row['occurred_at']?.toString() ?? '';
        return [
          occurred.length >= 16 ? occurred.substring(0, 16).replaceFirst('T', ' ') : occurred,
          row['actor_name'] ?? '',
          row['category'] ?? '',
          row['action'] ?? '',
          row['subject'] ?? '',
        ];
      }).toList(),
    );
    if (!downloadCsv(csvFileName('activity log'), csv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exporting works in the web admin portal.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterActivity(_rows, query: _query, category: _category);
    final isFiltered = _query.trim().isNotEmpty || _category != null;

    return Column(
      children: [
        AdminPageHeader(
          title: 'Activity',
          subtitle: 'Recent decisions and edits across the portal',
          actions: [
            if (_rows.isNotEmpty)
              TextButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export'),
              ),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 6, cardHeight: 72))
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _rows.isEmpty
              ? _emptyState(
                  icon: Icons.history,
                  title: 'No recorded activity yet',
                  message: 'Approvals, reviews and content edits appear here as admins make them.',
                )
              : Column(
                  children: [
                    AdminFilterBar(
                      searchHint: 'Search by person, action or subject',
                      searchController: _searchController,
                      onSearchChanged: (v) => setState(() => _query = v),
                      resultSummary: isFiltered ? '${visible.length} of ${_rows.length} entries' : null,
                      filters: [
                        AdminFilterGroup(
                          label: 'Type',
                          options: {
                            null: 'All',
                            for (final c in _categoryColors.keys) c: c,
                          },
                          selected: _category,
                          onChanged: (v) => setState(() => _category = v),
                        ),
                      ],
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? _emptyState(
                              icon: Icons.search_off,
                              title: 'No activity matches',
                              message: 'Nothing matches the current search and filters.',
                              action: TextButton.icon(
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  _query = '';
                                  _category = null;
                                }),
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear filters'),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: visible.length,
                                itemBuilder: (context, i) => _buildRow(visible[i]),
                              ),
                            ),
                    ),
                    if (_rows.length >= _limit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'Showing the $_limit most recent entries.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AdminPalette.of(context).ink.withValues(alpha: 0.5)),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final category = row['category'] as String? ?? '';
    final color = _categoryColors[category] ?? AdminTheme.harborBlue;
    final icon = _categoryIcons[category] ?? Icons.history;
    final occurredAt = DateTime.tryParse(row['occurred_at'] as String? ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text('${row['action'] ?? ''} ${row['subject'] ?? ''}'.trim()),
        subtitle: Text(
          '${row['actor_name'] ?? 'Unknown'}'
          '${occurredAt == null ? '' : ' · ${DateFormat('MMM d, yyyy h:mm a').format(occurredAt.toLocal())}'}',
          style: TextStyle(color: AdminPalette.of(context).ink.withValues(alpha: 0.6)),
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String message, Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AdminPalette.of(context).ink.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AdminPalette.of(context).ink)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AdminPalette.of(context).ink.withValues(alpha: 0.6))),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}
