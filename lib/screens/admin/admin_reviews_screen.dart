import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/admin_palette.dart';
import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';

/// Narrows loaded reviews by free text (station, reviewer, comment) and
/// rating band. Pure and top-level so it is unit-testable.
///
/// [band] is 'low' (1-2 stars), 'mid' (3) or 'high' (4-5); [withComment]
/// keeps only reviews that say something, the ones moderation is about.
List<Map<String, dynamic>> filterAdminReviews(
  List<Map<String, dynamic>> rows, {
  String query = '',
  String? band,
  bool withComment = false,
}) {
  final q = query.trim().toLowerCase();
  return rows.where((r) {
    final rating = (r['rating'] as num?)?.toInt() ?? 0;
    if (band == 'low' && rating > 2) return false;
    if (band == 'mid' && rating != 3) return false;
    if (band == 'high' && rating < 4) return false;
    final comment = (r['comment'] as String?)?.trim() ?? '';
    if (withComment && comment.isEmpty) return false;
    if (q.isEmpty) return true;
    final fields = [
      r['water_stations']?['station_name'] as String?,
      r['profiles']?['full_name'] as String?,
      comment,
    ];
    return fields.any((f) => f != null && f.toLowerCase().contains(q));
  }).toList();
}

/// Every station review, for officers to read and moderate.
///
/// Customers could leave a comment with their rating, but nothing in the
/// product ever showed one -- not to the station, not to the association --
/// so an abusive review could neither be seen nor removed. Removing one is
/// permanent; the station's average is recomputed at once.
class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  final _reviewService = ReviewService(SupabaseService.instance);
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _reviews = [];
  String _query = '';
  String? _band;
  String? _comments;
  String? _busyId;

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
      final rows = await _reviewService.fetchAllReviews();
      if (mounted) {
        setState(() {
          _reviews = rows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load reviews. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> review) async {
    final station = (review['water_stations']?['station_name'] as String?) ?? 'the station';
    final ok = await showConfirmDialog(
      context,
      title: 'Remove this review?',
      message: 'The ${review['rating']}-star review of $station is deleted permanently and the station\'s '
          'average rating is recalculated. Use this for abusive, false or off-topic reviews.',
      confirmLabel: 'Remove review',
    );
    if (!ok) return;
    final id = review['id'] as String;
    setState(() => _busyId = id);
    try {
      await _reviewService.deleteReview(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove the review. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterAdminReviews(_reviews, query: _query, band: _band, withComment: _comments == 'with');
    final isFiltered = _query.trim().isNotEmpty || _band != null || _comments != null;

    return Column(
      children: [
        AdminPageHeader(
          eyebrow: 'Content',
          title: 'Reviews',
          subtitle: _reviews.isEmpty ? 'What customers say about member stations' : '${_reviews.length} reviews',
        ),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 5))
              : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : _reviews.isEmpty
                      ? const PortalEmptyState(
                          icon: Icons.star_outline,
                          title: 'No reviews yet',
                          message: 'Customers can review a station after an order from it is delivered.',
                        )
                      : Column(
                          children: [
                            AdminFilterBar(
                              searchHint: 'Search by station, reviewer or comment',
                              searchController: _searchController,
                              onSearchChanged: (v) => setState(() => _query = v),
                              resultSummary: isFiltered ? '${visible.length} of ${_reviews.length} reviews' : null,
                              filters: [
                                AdminFilterGroup(
                                  label: 'Rating',
                                  options: const {null: 'Any', 'low': '1-2 stars', 'mid': '3 stars', 'high': '4-5 stars'},
                                  selected: _band,
                                  onChanged: (v) => setState(() => _band = v),
                                ),
                                AdminFilterGroup(
                                  label: 'Comment',
                                  options: const {null: 'Any', 'with': 'Has a comment'},
                                  selected: _comments,
                                  onChanged: (v) => setState(() => _comments = v),
                                ),
                              ],
                            ),
                            Expanded(
                              child: visible.isEmpty
                                  ? PortalEmptyState(
                                      icon: Icons.search_off,
                                      title: 'No reviews match',
                                      message: 'Nothing matches the current search and filters.',
                                      action: TextButton.icon(
                                        onPressed: () => setState(() {
                                          _searchController.clear();
                                          _query = '';
                                          _band = null;
                                          _comments = null;
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
                                        itemBuilder: (context, i) => _buildTile(visible[i]),
                                      ),
                                    ),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> review) {
    final palette = AdminPalette.of(context);
    final comment = (review['comment'] as String?)?.trim() ?? '';
    final busy = _busyId == review['id'];
    return PortalCard(
      lift: false,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (review['water_stations']?['station_name'] as String?) ?? 'Unknown station',
                  style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink),
                ),
              ),
              StarRatingDisplay(rating: ((review['rating'] as num?) ?? 0).toDouble()),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${(review['profiles']?['full_name'] as String?) ?? 'Deleted account'} · '
            '${DateFormat('MMM d, yyyy').format(DateTime.parse(review['created_at'] as String).toLocal())}',
            style: TextStyle(color: palette.inkMuted),
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: TextStyle(color: palette.ink)),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy || _busyId != null ? null : () => _delete(review),
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }
}
