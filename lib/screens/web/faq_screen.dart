import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Content-only accordion FAQ, modeled on the real CCWRSPO (UP Manila)
/// water refilling station operator FAQ structure -- questions an actual
/// station owner or resident would ask, answered from the real
/// accreditation/ordering mechanics already built (not invented policy).
const _faqs = [
  (
    'Who can order water through GENTRI WASA?',
    'Anyone can browse the station directory and community bulletin without an account. Placing an order requires a free customer account, so deliveries are tied to a real, trackable identity rather than anonymous device state.',
  ),
  (
    'How do I know a station is legitimate?',
    'Look for the green "WASA Verified" seal on the station directory and map. It only appears once every required permit has been reviewed and approved by a WASA admin -- a station cannot grant itself this seal.',
  ),
  (
    'What permits does a station need to get accredited?',
    'A Mayor\'s Business Permit, a Sanitary Permit, and an FDA License to Operate are required for every station. Stations offering alkaline water also need an Alkaline Machine Technical Certification and an Alkaline Water Quality Test Report.',
  ),
  (
    'How long does accreditation review take?',
    'There\'s no fixed timeline -- a WASA admin reviews each uploaded document individually and either approves it or rejects it with a stated reason, so an owner always knows exactly what to fix and can re-upload immediately.',
  ),
  (
    'Can I schedule a delivery instead of ordering ASAP?',
    'Yes -- the order form has an ASAP/Scheduled toggle. Choosing Scheduled lets you pick a future date and time for delivery instead of requesting the soonest available driver.',
  ),
  (
    'How do I pay?',
    'Cash on delivery. The total (jugs × price, plus delivery fee) is shown before you confirm the order and again when the driver arrives.',
  ),
  (
    'What is the floor price, and why does it exist?',
    'WASA sets a minimum price per water type across all member stations, so no station can undercut competitors to the point of predatory pricing. Every station\'s price must stay at or above this floor.',
  ),
  (
    'What happens if I have a problem with a driver or station?',
    'Station owners can file a security incident against a worker through the shared clearance registry, which follows that worker even if they move to another member station. Residents can reach the association directly through the Contact page.',
  ),
];

class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
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
      appBar: const WebNavBar(currentPage: WebPage.faq),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeSlideIn(
                            child: Text(t('faq_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('faq_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 24),
                          for (var i = 0; i < _faqs.length; i++)
                            FadeSlideIn(delay: Duration(milliseconds: 140 + i * 40), child: _buildFaqTile(_faqs[i].$1, _faqs[i].$2)),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w600)),
        iconColor: AppColors.primary,
        collapsedIconColor: AppColors.primary,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(answer, style: const TextStyle(height: 1.4, color: Colors.black87))],
      ),
    );
  }
}
