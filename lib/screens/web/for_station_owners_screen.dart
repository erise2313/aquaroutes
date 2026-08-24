import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../auth/registration_screen.dart';
import 'how_accreditation_works_screen.dart';

class ForStationOwnersScreen extends ConsumerStatefulWidget {
  const ForStationOwnersScreen({super.key});

  @override
  ConsumerState<ForStationOwnersScreen> createState() => _ForStationOwnersScreenState();
}

class _ForStationOwnersScreenState extends ConsumerState<ForStationOwnersScreen> {
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
      appBar: const WebNavBar(currentPage: WebPage.forOwners),
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
                            child: Text(t('for_owners_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 16),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('for_owners_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          const Text('Why Join', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: const [
                              FadeSlideIn(
                                delay: Duration(milliseconds: 140),
                                child: _BenefitCard(icon: Icons.verified, title: 'Official Recognition', body: 'Accredited stations get the WASA verification seal on the public directory and map.'),
                              ),
                              FadeSlideIn(
                                delay: Duration(milliseconds: 200),
                                child: _BenefitCard(icon: Icons.security, title: 'Worker Accountability', body: 'Screen prospective drivers/helpers against the shared cross-station clearance registry before hiring.'),
                              ),
                              FadeSlideIn(
                                delay: Duration(milliseconds: 260),
                                child: _BenefitCard(icon: Icons.price_change, title: 'Fair Pricing Protection', body: 'Association-wide floor prices protect member stations from predatory undercutting.'),
                              ),
                              FadeSlideIn(
                                delay: Duration(milliseconds: 320),
                                child: _BenefitCard(icon: Icons.swap_horiz, title: 'Jug Clearinghouse', body: 'Settle Slim/Round 5-gallon jug balances with other stations through one shared ledger.'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 380),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('What You\'ll Need', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                const Text(
                                  'Business Permit, Sanitary Permit, and FDA License to Operate at minimum -- plus two additional certifications if you offer alkaline water.',
                                  style: TextStyle(color: Colors.grey, height: 1.4),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HowAccreditationWorksScreen())),
                                  child: const Text('See the full accreditation process'),
                                ),
                                const SizedBox(height: 24),
                                HoverScale(
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                                    child: Text(t('for_owners_cta'), style: const TextStyle(color: Colors.white, fontSize: 16)),
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
          child: Card(
            elevation: _hovering ? 4 : 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, color: AppColors.primary, size: 28),
                  const SizedBox(height: 12),
                  Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(widget.body, style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
