import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import 'stations_directory_screen.dart';

/// Placeholder contact details -- no real WASA office address/hours/phone
/// exist yet, so these are obviously marked as such rather than invented.
/// The email uses url_launcher's mailto: (already a dependency) instead of
/// a form, since there's no backend to receive form submissions.
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
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.contact),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeSlideIn(
                            child: Text(t('contact_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('contact_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 140),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _contactRow(Icons.location_on_outlined, '[Placeholder] Association Office Address, General Trias, Cavite'),
                                    const Divider(height: 24),
                                    _contactRow(Icons.access_time, '[Placeholder] Office Hours: Monday-Friday, 8:00 AM - 5:00 PM'),
                                    const Divider(height: 24),
                                    InkWell(
                                      onTap: () => launchUrl(Uri.parse('mailto:contact@gentriwasa.example')),
                                      child: _contactRow(Icons.email_outlined, 'contact@gentriwasa.example', isLink: true),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 48),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 220),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.08), AppColors.accent.withValues(alpha: 0.08)]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(children: [Icon(Icons.storefront, color: AppColors.primary), SizedBox(width: 10), Text('Looking for a water station instead?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Browse every accredited station in General Trias, filter by water type or barangay, and see them on the map.',
                                    style: TextStyle(color: Colors.black87, height: 1.4),
                                  ),
                                  const SizedBox(height: 16),
                                  HoverScale(
                                    child: OutlinedButton.icon(
                                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StationsDirectoryScreen())),
                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                                      icon: const Icon(Icons.map_outlined),
                                      label: const Text('Browse the Stations Directory'),
                                    ),
                                  ),
                                ],
                              ),
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
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, decoration: isLink ? TextDecoration.underline : null, color: isLink ? AppColors.primary : Colors.black87),
          ),
        ),
      ],
    );
  }
}
