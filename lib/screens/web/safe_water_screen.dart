import 'package:flutter/material.dart';

import '../../constants/web_theme.dart';
import '../../models/web_content.dart';
import '../../services/supabase_service.dart';
import '../../services/web_content_service.dart';
import '../../utils/error_text.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';

/// web_content_items.icon is a name (it isn't persistable as IconData);
/// these are the ones the safe-water articles use. Anything else falls back
/// to a water drop.
const safeWaterIcons = <String, IconData>{
  'science': Icons.science_outlined,
  'cleaning_services': Icons.cleaning_services_outlined,
  'kitchen': Icons.kitchen_outlined,
  'verified': Icons.verified_outlined,
  'water_drop': Icons.water_drop_outlined,
};

/// Loads the safe-water articles (page 'safe_water', items 'articles',
/// seeded by patch_public_trust.sql, editable in Admin -> Website).
Future<List<WebContentItem>> fetchSafeWaterArticles() =>
    WebContentService(SupabaseService.instance).fetchItems('safe_water', 'articles');

/// Plain advice for households: what a water test means, keeping jugs
/// clean, storing water, and what accreditation does and doesn't promise.
class SafeWaterScreen extends StatefulWidget {
  const SafeWaterScreen({super.key});

  @override
  State<SafeWaterScreen> createState() => _SafeWaterScreenState();
}

class _SafeWaterScreenState extends State<SafeWaterScreen> {
  final _scrollController = ScrollController();
  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _articles = [];

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
      final articles = await fetchSafeWaterArticles();
      if (mounted) {
        setState(() {
          _articles = articles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this page. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WebTheme.of(context);
    return Scaffold(
      backgroundColor: palette.paper,
      appBar: const WebNavBar(currentPage: WebPage.safeWater),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                const FadeSlideIn(
                  child: WebPageHeader(
                    eyebrow: 'FOR HOUSEHOLDS',
                    title: 'Safe drinking water',
                    subtitle: 'What to look for in refilled water, and how to keep it clean at home.',
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 4, cardHeight: 80)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_articles.isEmpty)
                                      Text(
                                        'These articles have not been published yet.',
                                        style: TextStyle(color: palette.inkMuted, fontStyle: FontStyle.italic),
                                      ),
                                    for (final a in _articles)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: palette.foam,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: palette.border),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(safeWaterIcons[a.icon] ?? Icons.water_drop_outlined, color: WebTheme.harborBlue, size: 28),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(a.title, style: WebTheme.display(fontSize: 22)),
                                                  const SizedBox(height: 8),
                                                  Text(a.body, style: TextStyle(fontSize: 18, height: 1.6, color: palette.ink)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
}
