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
import '../../widgets/web_seal.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _whatWasaDoes = [];
  List<String> _barangays = [];

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
      final items = await _webContentService.fetchItems('about', 'what_wasa_does');
      // Live query instead of a hardcoded duplicate -- this used to be a
      // static const list that had to be kept in sync with the real
      // barangays table by hand.
      final rows = await SupabaseService.instance.client.from('barangays').select('name').order('name');
      final barangays = List<Map<String, dynamic>>.from(rows).map((r) => r['name'] as String).toList();
      if (mounted) {
        setState(() {
          _whatWasaDoes = items;
          _barangays = barangays;
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
      appBar: const WebNavBar(currentPage: WebPage.about),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'ABOUT THE ASSOCIATION', title: t('about_title'), subtitle: t('about_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 4, cardHeight: 40)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('What WASA Does', style: WebTheme.display(fontSize: 22)),
                          const SizedBox(height: 16),
                          for (final item in _whatWasaDoes) _bulletPoint(item.body),
                          const SizedBox(height: 40),
                          Text('Coverage Area', style: WebTheme.display(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text('GENTRI WASA covers all barangays of General Trias, Cavite:', style: TextStyle(color: WebTheme.of(context).inkMuted)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _barangays
                                .map((b) => Chip(
                                      label: Text(b, style: TextStyle(fontSize: 12, color: WebTheme.of(context).ink)),
                                      backgroundColor: WebTheme.of(context).foam,
                                      side: BorderSide.none,
                                    ))
                                .toList(),
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

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2, right: 12), child: WebSeal(size: 18, outlined: true)),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, height: 1.5, color: WebTheme.of(context).ink))),
        ],
      ),
    );
  }
}
