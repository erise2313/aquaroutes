import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/web_theme.dart';
import '../../providers/web_locale_provider.dart';
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
import 'stations_directory_screen.dart';

/// Address/hours/email are admin-editable (web_page_sections, page_key
/// 'contact') -- still placeholder text by default until WASA supplies
/// real office details, but now something admin can update themselves
/// instead of needing a code change. The email uses url_launcher's
/// mailto: (already a dependency) instead of a form, since there's no
/// backend to receive form submissions.
///
/// The card alone left a large empty region below it on tall viewports
/// (reported via screenshot) -- a "Find a station instead" section fills
/// that gap with a real, useful secondary action rather than empty space.
class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  final _webContentService = WebContentService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  Map<String, String> _sections = {};

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
      final sections = await _webContentService.fetchSections('contact');
      if (mounted) {
        setState(() {
          _sections = {for (final s in sections) s.sectionKey: s.body};
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
    final email = _sections['email'] ?? 'contact@gentriwasa.example';

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.contact),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'GET IN TOUCH', title: t('contact_title'), subtitle: t('contact_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: _isLoading
                          ? const SkeletonList(count: 3, cardHeight: 40)
                          : _error != null
                              ? ErrorState(message: _error!, onRetry: _load)
                              : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            decoration: BoxDecoration(color: WebTheme.of(context).card, borderRadius: BorderRadius.circular(12), border: Border.all(color: WebTheme.of(context).foam, width: 2)),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _contactRow(Icons.location_on_outlined, _sections['address'] ?? '[Placeholder] Association Office Address, General Trias, Cavite'),
                                const Divider(height: 24),
                                _contactRow(Icons.access_time, _sections['hours'] ?? '[Placeholder] Office Hours: Monday-Friday, 8:00 AM - 5:00 PM'),
                                const Divider(height: 24),
                                InkWell(
                                  onTap: () => launchUrl(Uri.parse('mailto:$email')),
                                  child: _contactRow(Icons.email_outlined, email, isLink: true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 48),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: WebTheme.of(context).foam, borderRadius: BorderRadius.circular(12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [Icon(Icons.storefront, color: WebTheme.harborBlue), SizedBox(width: 10), Text('Looking for a water station instead?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: WebTheme.of(context).ink))]),
                                const SizedBox(height: 8),
                                Text(
                                  'Browse every accredited station in General Trias, filter by water type or barangay, and see them on the map.',
                                  style: TextStyle(color: WebTheme.of(context).ink, height: 1.4),
                                ),
                                const SizedBox(height: 16),
                                HoverScale(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.push(context, webPageRoute(const StationsDirectoryScreen())),
                                    style: OutlinedButton.styleFrom(foregroundColor: WebTheme.harborBlue, side: const BorderSide(color: WebTheme.harborBlue)),
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('Browse the Stations Directory'),
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

  Widget _contactRow(IconData icon, String text, {bool isLink = false}) {
    return Row(
      children: [
        Icon(icon, color: WebTheme.harborBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, decoration: isLink ? TextDecoration.underline : null, color: isLink ? WebTheme.harborBlue : WebTheme.of(context).ink),
          ),
        ),
      ],
    );
  }
}
