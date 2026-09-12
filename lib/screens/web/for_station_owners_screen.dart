import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../constants/web_theme.dart';
import '../../models/web_content.dart';
import '../../providers/app_state.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_router.dart';
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
import 'how_accreditation_works_screen.dart';
import '../../utils/error_text.dart';

/// IconData is not persistable, so `web_content_items.icon` for this page's
/// benefit cards stores a short string key (see patch_website_content_cms.sql's
/// seed) resolved back to an actual icon here.
const _benefitIcons = {
  'verified': Icons.verified,
  'security': Icons.security,
  'price_change': Icons.price_change,
  'swap_horiz': Icons.swap_horiz,
};

class ForStationOwnersScreen extends ConsumerStatefulWidget {
  const ForStationOwnersScreen({super.key});

  @override
  ConsumerState<ForStationOwnersScreen> createState() => _ForStationOwnersScreenState();
}

class _ForStationOwnersScreenState extends ConsumerState<ForStationOwnersScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<WebContentItem> _benefits = [];
  String _requirementsSummary = '';

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
      final benefits = await _webContentService.fetchItems('for_station_owners', 'benefits');
      final sections = await _webContentService.fetchSections('for_station_owners');
      if (mounted) {
        setState(() {
          _benefits = benefits;
          _requirementsSummary = sections.firstWhere(
            (s) => s.sectionKey == 'requirements_summary',
            orElse: () => const WebPageSection(id: '', pageKey: 'for_station_owners', sectionKey: 'requirements_summary', body: '', sortOrder: 0),
          ).body;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page. ${describeError(e)}'; _isLoading = false; });
    }
  }

  /// Navigates by URL where a router is present, exactly as the nav bar and
  /// the footer do, so the site's pages stay siblings rather than a stack.
  /// The push is the fallback for the non-routed builds that reuse this
  /// screen.
  void _goToAccreditation(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(WebRoutes.accreditation);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(webPageRoute(const HowAccreditationWorksScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.forOwners),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'JOIN THE ASSOCIATION', title: t('for_owners_title'), subtitle: t('for_owners_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 4, cardHeight: 60)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Why Join', style: WebTheme.display(fontSize: 22)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final b in _benefits)
                                _BenefitCard(icon: _benefitIcons[b.icon] ?? Icons.check_circle, title: b.title, body: b.body),
                            ],
                          ),
                          const SizedBox(height: 40),
                          Text('What You\'ll Need', style: WebTheme.display(fontSize: 22)),
                          const SizedBox(height: 8),
                          // An empty CMS row rendered as a blank gap under a
                          // visible heading, which reads as a broken page
                          // rather than as missing content.
                          Text(
                            _requirementsSummary.trim().isEmpty
                                ? 'The requirements summary has not been published yet. See the full accreditation process below for what you\'ll need.'
                                : _requirementsSummary,
                            style: TextStyle(
                              color: WebTheme.of(context).inkMuted,
                              height: 1.4,
                              fontStyle: _requirementsSummary.trim().isEmpty ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          TextButton(
                            // Was a Navigator.push, which stranded the whole
                            // site: it stacked a route *above* the router's
                            // page, so every header link afterwards changed
                            // the URL while navigating underneath the pushed
                            // screen -- the address bar moved and the page
                            // did not. Accreditation is a sibling page, so it
                            // navigates like one.
                            onPressed: () => _goToAccreditation(context),
                            style: TextButton.styleFrom(foregroundColor: WebTheme.harborBlue),
                            child: const Text('See the full accreditation process'),
                          ),
                          // Registering is for visitors: someone already
                          // signed in has a station, and this asked them to
                          // register another one.
                          if (!ref.watch(isSignedInProvider)) ...[
                            const SizedBox(height: 24),
                            HoverScale(
                              child: ElevatedButton(
                                // Still a push: registration is a drill-down
                                // from this page, not one of the site's
                                // sibling pages.
                                onPressed: () => Navigator.push(context, webPageRoute(const RegistrationScreen())),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WebTheme.harborBlue,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                child: Text(t('for_owners_cta'), style: const TextStyle(color: Colors.white, fontSize: 16)),
                              ),
                            ),
                          ],
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

class _BenefitCard extends StatefulWidget {
  const _BenefitCard({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  State<_BenefitCard> createState() => _BenefitCardState();
}

class _BenefitCardState extends State<_BenefitCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          width: 260,
          child: Container(
            decoration: BoxDecoration(
              color: WebTheme.of(context).foam,
              borderRadius: BorderRadius.circular(10),
              boxShadow: _hovering ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, 4))] : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, color: WebTheme.harborBlue, size: 26),
                  const SizedBox(height: 14),
                  Text(widget.title, style: TextStyle(fontWeight: FontWeight.bold, color: WebTheme.of(context).ink)),
                  const SizedBox(height: 6),
                  Text(widget.body, style: TextStyle(color: WebTheme.of(context).inkMuted, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
