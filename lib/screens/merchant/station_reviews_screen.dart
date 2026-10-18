import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/review_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/star_rating.dart';

/// What customers have said about the owner's station.
///
/// Customers could rate a station and leave a comment after a delivery, but
/// the station never saw either -- only the average on its public listing.
/// Reviewers are shown without their names: a customer's profile is private
/// to them and to WASA. A review the owner thinks is abusive or false is
/// for WASA to remove (Admin portal, Reviews), which this screen says.
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
      if (mounted) {
        setState(() {
          _hasStation = true;
          _reviews = reviews;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Your station',
            title: 'Customer Reviews',
            subtitle: 'Ratings and comments customers leave after a delivery',
          ),
          Expanded(child: _buildBody()),
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
