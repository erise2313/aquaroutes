import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/web_theme.dart';
import '../../models/web_content.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/permit_service.dart';
import '../../services/supabase_service.dart';
import '../../services/web_content_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_page_route.dart';
import '../auth/registration_screen.dart';
import '../../utils/error_text.dart';

class HowAccreditationWorksScreen extends ConsumerStatefulWidget {
  const HowAccreditationWorksScreen({super.key});

  @override
  ConsumerState<HowAccreditationWorksScreen> createState() => _HowAccreditationWorksScreenState();
}

class _HowAccreditationWorksScreenState extends ConsumerState<HowAccreditationWorksScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _permitService = PermitService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _steps = [];
  List<PermitTypeLabel> _permitLabels = [];

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
      final steps = await _webContentService.fetchItems('how_accreditation_works', 'steps');
      final labels = await _permitService.fetchPermitLabels();
      if (mounted) {
        setState(() {
          _steps = steps;
          _permitLabels = labels;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page. ${describeError(e)}'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.howItWorks),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'THE PROCESS', title: t('how_it_works_title'), subtitle: t('how_it_works_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 5, cardHeight: 60)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _steps.length; i++) _stepTile(i + 1, _steps[i].title, _steps[i].body),
                          const SizedBox(height: 24),
                          Text('Required Documents', style: WebTheme.display(fontSize: 22)),
                          const SizedBox(height: 12),
                          ..._permitLabels.map(
                            (p) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(color: WebTheme.of(context).foam, borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: const Icon(Icons.description_outlined, color: WebTheme.harborBlue),
                                title: Text(p.label, style: TextStyle(color: WebTheme.of(context).ink, fontWeight: FontWeight.w600)),
                                subtitle: Text(p.conditionNote),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          HoverScale(
                            child: ElevatedButton(
                              onPressed: () => Navigator.push(context, webPageRoute(const RegistrationScreen())),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WebTheme.harborBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              child: Text(t('for_owners_cta'), style: const TextStyle(color: Colors.white)),
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

  Widget _stepTile(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: WebTheme.harborBlue,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
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
