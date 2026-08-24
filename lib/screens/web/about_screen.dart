import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Static coverage-area list -- mirrors the barangays seeded for the
/// association (supabase/reset_and_rebuild.sql / 0010_seed_gentri_wasa.sql).
/// Not queried live since it's fixed reference content, not user data.
const _barangays = [
  'Alingaro', 'Arnaldo (Poblacion 7)', 'Bacao I', 'Bacao II', 'Bagumbayan (Poblacion 5)',
  'Biclatan', 'Buenavista I', 'Buenavista II', 'Buenavista III', 'Corregidor (Poblacion 10)',
  'Dulong Bayan (Poblacion 3)', 'Gov. Ferrer (Poblacion 1)', 'Javalera', 'Manggahan', 'Navarro',
  'Ninety Sixth (Poblacion 8)', 'Panungyanan', 'Pasong Camachile I', 'Pasong Camachile II',
  'Pasong Kawayan I', 'Pasong Kawayan II', 'Pinagtipunan', 'Prinza (Poblacion 9)',
  'Sampalucan (Poblacion 2)', 'San Francisco', 'San Gabriel (Poblacion 4)', 'San Juan I',
  'San Juan II', 'Santa Clara', 'Santiago', 'Tapia', 'Tejero', 'Vibora (Poblacion 6)',
];

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
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
      appBar: const WebNavBar(currentPage: WebPage.about),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeSlideIn(
                            child: Text(t('about_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 16),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('about_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 140),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('What WASA Does', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                _bulletPoint('Reviews and accredits refilling stations before they can display the WASA verification seal.'),
                                _bulletPoint('Maintains a shared worker security registry, so a driver flagged for an incident at one station can\'t simply move to another unnoticed.'),
                                _bulletPoint('Sets and enforces minimum floor prices to prevent predatory undercutting between member stations.'),
                                _bulletPoint('Coordinates the inter-station jug clearinghouse, so reusable 5-gallon containers get settled fairly between stations.'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 200),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Coverage Area', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text('GENTRI WASA covers all barangays of General Trias, Cavite:', style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _barangays
                                      .map((b) => Chip(label: Text(b, style: const TextStyle(fontSize: 12)), backgroundColor: AppColors.primary.withValues(alpha: 0.08)))
                                      .toList(),
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

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 6, right: 10), child: Icon(Icons.circle, size: 6, color: AppColors.primary)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}
