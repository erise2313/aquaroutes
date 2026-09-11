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

/// Content-only explainer for the jug clearinghouse -- a genuine
/// differentiator no comparable chamber/AMS site template has, so it earns
/// its own page. Mechanics described here are pulled from the real
/// implementation (jug_ledger_service.dart / jug_ledger_entries /
/// jug_balances / propose-confirm-reject settlement RPCs), not invented.
/// Content is admin-editable (web_page_sections/web_content_items,
/// page_key 'jug_clearinghouse') rather than hardcoded here.
class JugClearinghouseExplainerScreen extends ConsumerStatefulWidget {
  const JugClearinghouseExplainerScreen({super.key});

  @override
  ConsumerState<JugClearinghouseExplainerScreen> createState() => _JugClearinghouseExplainerScreenState();
}

class _JugClearinghouseExplainerScreenState extends ConsumerState<JugClearinghouseExplainerScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  String _intro = '';
  List<WebContentItem> _steps = [];

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
      final sections = await _webContentService.fetchSections('jug_clearinghouse');
      final steps = await _webContentService.fetchItems('jug_clearinghouse', 'steps');
      if (mounted) {
        setState(() {
          _intro = sections.firstWhere(
            (s) => s.sectionKey == 'intro',
            orElse: () => const WebPageSection(id: '', pageKey: 'jug_clearinghouse', sectionKey: 'intro', body: '', sortOrder: 0),
          ).body;
          _steps = steps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.jugClearinghouse),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'HOW IT WORKS', title: t('jug_clearinghouse_title'), subtitle: t('jug_clearinghouse_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 4, cardHeight: 60)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Skipped entirely when unset: an empty gold callout
                          // box is a more obvious defect than simply not
                          // showing an intro that hasn't been written.
                          if (_intro.trim().isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: WebTheme.of(context).foam, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: WebTheme.sealGold, width: 4))),
                              child: Text(
                                _intro,
                                style: TextStyle(height: 1.5, color: WebTheme.of(context).ink),
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                          if (_steps.isEmpty)
                            Text(
                              'The step-by-step explainer has not been published yet.',
                              style: TextStyle(color: WebTheme.of(context).inkMuted, fontStyle: FontStyle.italic),
                            ),
                          for (var i = 0; i < _steps.length; i++) _buildStep(i + 1, _steps[i].title, _steps[i].body),
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

  Widget _buildStep(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, backgroundColor: WebTheme.harborBlue, child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: WebTheme.of(context).ink)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: WebTheme.of(context).inkMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
