import 'package:flutter/material.dart';

import '../constants/admin_theme.dart';
import '../constants/admin_palette.dart';

/// One row of mutually-exclusive filter choices (e.g. Role: Any / Owner /
/// Driver). [options] maps the value stored in [selected] to its label; a
/// null key is the "no filter" choice and is always rendered first.
class AdminFilterGroup {
  const AdminFilterGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final Map<String?, String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;
}

/// Search box plus chip filters, shared by the admin list screens.
///
/// Chips rather than dropdowns on purpose: the portal's users skew older, and
/// a chip shows every option and the current selection at a glance instead of
/// hiding both behind a tap. It also makes "why am I seeing so few rows?"
/// answerable without opening anything.
class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.searchHint,
    required this.searchController,
    required this.onSearchChanged,
    this.filters = const [],
    this.resultSummary,
  });

  final String searchHint;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<AdminFilterGroup> filters;

  /// e.g. "12 of 48 accounts" -- shown only when a filter is narrowing the
  /// list, so an admin can tell a filtered view from an empty table.
  final String? resultSummary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear search',
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          for (final group in filters) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Text(
                    group.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AdminPalette.of(context).ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: group.options.entries
                        .map((e) => ChoiceChip(
                              label: Text(e.value),
                              selected: group.selected == e.key,
                              onSelected: (_) => group.onChanged(e.key),
                              selectedColor: AdminTheme.harborBlue.withValues(alpha: 0.16),
                              labelStyle: TextStyle(
                                fontWeight: group.selected == e.key ? FontWeight.w700 : FontWeight.w500,
                                color: AdminPalette.of(context).ink,
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
          if (resultSummary != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                resultSummary!,
                style: TextStyle(color: AdminPalette.of(context).ink.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}
