import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/bulletin.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/bulletin_service.dart';
import '../../services/supabase_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Full news history for the website -- reuses BulletinService.fetchBulletins()
/// (the same query backing bulletin_feed.dart's mobile board) rather than a
/// separate query, with category filtering and the pinned post promoted to
/// a larger featured card.
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  final _bulletinService = BulletinService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<Bulletin> _bulletins = [];
  BulletinCategory? _filter;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bulletins = await _bulletinService.fetchBulletins();
      if (mounted) {
        setState(() {
          _bulletins = bulletins;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load news: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Bulletin> get _filtered {
    if (_filter == null) return _bulletins;
    return _bulletins.where((b) => b.category == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    final filtered = _filtered;
    final featured = _filter == null ? _bulletins.where((b) => b.isPinned).toList() : <Bulletin>[];
    final rest = filtered.where((b) => !featured.contains(b)).toList();

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.news),
      body: Stack(
        children: [
          _isLoading
              ? SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBlock(width: 180, height: 28),
                            SizedBox(height: 24),
                            SkeletonList(count: 4, cardHeight: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FadeSlideIn(
                              child: Text(t('news_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 16),
                            FadeSlideIn(
                              delay: const Duration(milliseconds: 80),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _filterChip('All', null),
                                    const SizedBox(width: 8),
                                    _filterChip('Announcements', BulletinCategory.announcement),
                                    const SizedBox(width: 8),
                                    _filterChip('Price Changes', BulletinCategory.priceChange),
                                    const SizedBox(width: 8),
                                    _filterChip('Events', BulletinCategory.event),
                                    const SizedBox(width: 8),
                                    _filterChip('Discussion', BulletinCategory.discussion),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            for (var i = 0; i < featured.length; i++)
                              FadeSlideIn(delay: Duration(milliseconds: 140 + i * 60), child: _buildFeaturedCard(featured[i])),
                            if (featured.isNotEmpty) const SizedBox(height: 8),
                            if (filtered.isEmpty) const Text('No posts yet.', style: TextStyle(color: Colors.grey)),
                            for (var i = 0; i < rest.length; i++)
                              FadeSlideIn(delay: Duration(milliseconds: 140 + (featured.length + i) * 60), child: _buildCard(rest[i])),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const WebFooter(),
                ],
              ),
            ),
          BackToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  Widget _filterChip(String label, BulletinCategory? category) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == category,
      onSelected: (_) => setState(() => _filter = category),
    );
  }

  Widget _buildFeaturedCard(Bulletin bulletin) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [Icon(Icons.push_pin, size: 16, color: Colors.amber), SizedBox(width: 6), Text('Pinned', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))]),
            const SizedBox(height: 8),
            Text(bulletin.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 8),
            Text(bulletin.body, style: const TextStyle(fontSize: 15, height: 1.4)),
            if (bulletin.imageUrl != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  bulletin.imageUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 220,
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text('${bulletin.authorBadge} · ${DateFormat('MMM d, yyyy').format(bulletin.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Bulletin bulletin) {
    final (categoryColor, categoryLabel) = switch (bulletin.category) {
      BulletinCategory.announcement => (Colors.indigo, 'Announcement'),
      BulletinCategory.priceChange => (Colors.teal, 'Price Change'),
      BulletinCategory.event => (Colors.deepOrange, 'Event'),
      BulletinCategory.discussion => (Colors.blueGrey, 'Discussion'),
    };

    return HoverScale(
      scale: 1.01,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: categoryColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(categoryLabel, style: TextStyle(color: categoryColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text(bulletin.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Text(bulletin.body),
              const SizedBox(height: 8),
              Text('${bulletin.authorBadge} · ${DateFormat('MMM d, yyyy').format(bulletin.createdAt)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
