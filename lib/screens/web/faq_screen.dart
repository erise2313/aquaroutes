import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/web_theme.dart';
import '../../models/web_content.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/supabase_service.dart';
import '../../services/web_content_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<WebFaqEntry> _faqs = [];

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
      final faqs = await _webContentService.fetchFaqs();
      if (mounted) setState(() { _faqs = faqs; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load the FAQ: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.faq),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'QUESTIONS ANSWERED', title: t('faq_title'), subtitle: t('faq_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 6, cardHeight: 52)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final faq in _faqs) _buildFaqTile(faq.question, faq.answer),
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

  Widget _buildFaqTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: WebTheme.of(context).foam, borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        title: Text(question, style: TextStyle(fontWeight: FontWeight.w600, color: WebTheme.of(context).ink)),
        iconColor: WebTheme.harborBlue,
        collapsedIconColor: WebTheme.harborBlue,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(answer, style: TextStyle(height: 1.4, color: WebTheme.of(context).ink))],
      ),
    );
  }
}
