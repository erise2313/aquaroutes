import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/error_state.dart';
import '../../constants/brand_tokens.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/report_problem_dialog.dart';
import '../../widgets/star_rating.dart';

/// What customers have said about the owner's station.
///
/// Customers could rate a station and leave a comment after a delivery, but
/// the station never saw either -- only the average on its public listing.
/// Reviewers are shown without their names: a customer's profile is private
/// to them and to WASA. A review the owner thinks is abusive or false is
/// for WASA to remove (Admin portal, Reviews), which this screen says.
///
/// The second tab lists problems customers reported to WASA about the
/// station (owner_list_reports, patch_public_trust.sql) -- what and when,
/// never who -- and lets the owner answer each one in writing.
class StationReviewsScreen extends StatefulWidget {
  const StationReviewsScreen({super.key});

  @override
  State<StationReviewsScreen> createState() => _StationReviewsScreenState();
}

class _StationReviewsScreenState extends State<StationReviewsScreen> {
  final _supabase = Supabase.instance.client;
  final _reviewService = ReviewService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  bool _hasStation = true;
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _reports = [];

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
      final userId = _supabase.auth.currentUser!.id;
      final station = await _supabase.from('water_stations').select('id').eq('owner_profile_id', userId).maybeSingle();
      if (station == null) {
        if (mounted) {
          setState(() {
            _hasStation = false;
            _isLoading = false;
          });
        }
        return;
      }
      final reviews = await _reviewService.fetchStationReviews(station['id'] as String);
      final reports = await _supabase.rpc('owner_list_reports');
      if (mounted) {
        setState(() {
          _hasStation = true;
          _reviews = reviews;
          _reports = List<Map<String, dynamic>>.from(reports as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your reviews. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _respond(Map<String, dynamic> report) async {
    final controller = TextEditingController(text: report['station_response'] as String?);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your response to WASA'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(report['details'] as String),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'What happened, and what you did about it'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Send response')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await _supabase.rpc('owner_respond_report', params: {'p_report_id': report['id'], 'p_response': text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Response sent to WASA.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _reports.where((r) => r['status'] == 'new' || r['status'] == 'reviewing').length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            PortalPageHeader(
              eyebrow: 'Your station',
              title: 'Customer Reviews',
              subtitle: 'Ratings customers leave after a delivery, and problems they reported to WASA',
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Reviews (${_reviews.length})'),
                  Tab(text: 'Reports to WASA${open > 0 ? ' ($open open)' : ''}'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildBody(),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? ErrorState(message: _error!, onRetry: _load)
                          : _buildReports(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReports() {
    final theme = Theme.of(context);
    if (_reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 48),
            PortalEmptyState(
              icon: Icons.flag_outlined,
              title: 'No reports',
              message: 'If a customer reports a problem with your water or a delivery to WASA, it appears here '
                  'so you can answer it. You are not told who reported it.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: PortalDensity.of(context).pagePadding,
        children: [
          for (final r in _reports)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(stationReportCategories[r['category']] ?? '', style: theme.textTheme.titleMedium),
                      StatusPill(
                        label: stationReportStatuses[r['status']] ?? '',
                        color: switch (r['status']) {
                          'resolved' => BrandStatus.success,
                          'reviewing' => BrandStatus.warning,
                          'dismissed' => Colors.blueGrey,
                          _ => BrandStatus.info,
                        },
                      ),
                    ],
                  ),
                  Text(
                    '${DateFormat('MMM d, yyyy').format(DateTime.parse(r['created_at'] as String).toLocal())}'
                    '${r['about_an_order'] == true ? ' · about a delivery' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(r['details'] as String),
                  if (r['officer_note'] != null) ...[
                    const SizedBox(height: 6),
                    Text("WASA's note: ${r['officer_note']}", style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                  if (r['station_response'] != null) ...[
                    const SizedBox(height: 6),
                    Text('Your response: ${r['station_response']}', style: theme.textTheme.bodySmall),
                  ],
                  if (r['status'] == 'new' || r['status'] == 'reviewing') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _respond(r),
                      icon: const Icon(Icons.edit_note),
                      label: Text(r['station_response'] == null ? 'Respond in writing' : 'Edit your response'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (!_hasStation) {
      return const PortalEmptyState(
        icon: Icons.storefront_outlined,
        title: 'No station linked to this account',
        message: 'Reviews appear here once your account is linked to a water station.',
      );
    }
    if (_reviews.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 48),
            PortalEmptyState(
              icon: Icons.star_outline,
              title: 'No reviews yet',
              message: 'Customers can review your station once an order from it has been delivered.',
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final density = PortalDensity.of(context);
    final average = _reviews.map((r) => (r['rating'] as num).toDouble()).reduce((a, b) => a + b) / _reviews.length;
    final counts = {for (var s = 5; s >= 1; s--) s: _reviews.where((r) => (r['rating'] as num).toInt() == s).length};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: density.pagePadding,
        children: [
          PortalCard(
            lift: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(average.toStringAsFixed(1), style: theme.textTheme.displaySmall),
                    StarRatingDisplay(rating: average, reviewCount: _reviews.length),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in counts.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(width: 24, child: Text('${e.key}★', style: theme.textTheme.bodySmall)),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: _reviews.isEmpty ? 0 : e.value / _reviews.length,
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              SizedBox(width: 32, child: Text('${e.value}', textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A review you believe is abusive or false? Contact WASA -- the association can remove it.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: density.gap),
          for (final r in _reviews)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StarRatingDisplay(rating: (r['rating'] as num).toDouble()),
                      const Spacer(),
                      Text(
                        DateFormat('MMM d, yyyy').format(DateTime.parse(r['created_at'] as String).toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (((r['comment'] as String?)?.trim() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text((r['comment'] as String).trim()),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('No comment', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
