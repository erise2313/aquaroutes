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

/// Mirrors the real permit_type enum (supabase/migrations/0004_permits.sql)
/// so this explainer can't silently drift out of sync with what the system
/// actually requires -- if a permit type is ever added/removed there, this
/// list is the one place to update.
const _requiredPermits = [
  ("Mayor's Business Permit", 'Required for every station.'),
  ('Sanitary Permit', 'Required for every station.'),
  ('FDA License to Operate', 'Required for every station.'),
  ('Alkaline Machine Technical Certification', 'Only required if the station offers alkaline water.'),
  ('Alkaline Water Quality Test Report', 'Only required if the station offers alkaline water.'),
];

class HowAccreditationWorksScreen extends ConsumerStatefulWidget {
  const HowAccreditationWorksScreen({super.key});

  @override
  ConsumerState<HowAccreditationWorksScreen> createState() => _HowAccreditationWorksScreenState();
}

class _HowAccreditationWorksScreenState extends ConsumerState<HowAccreditationWorksScreen> {
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

    final steps = [
      ('Register the station', 'The owner creates an account and registers their station with basic details (name, address, offered water types).'),
      ('Upload required documents', 'Every station uploads its Business Permit, Sanitary Permit, and FDA License. Stations offering alkaline water also upload two additional certifications.'),
      ('WASA reviews each document', 'A WASA admin reviews every uploaded document individually -- approving, or rejecting with a stated reason so the owner knows exactly what to fix.'),
      ('Accreditation is automatic once complete', 'The moment every required document is approved, the station is automatically marked accredited -- no separate manual step, and no way for a station to grant itself accreditation.'),
      ('The colorum-verification seal appears', 'Accredited, WASA-verified stations get the verification seal on the public station directory, so residents can tell a legitimate operator from an unlicensed one at a glance.'),
    ];

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.howItWorks),
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
                            child: Text(t('how_it_works_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 16),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('how_it_works_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          for (var i = 0; i < steps.length; i++)
                            FadeSlideIn(
                              delay: Duration(milliseconds: 140 + i * 60),
                              child: _stepTile(i + 1, steps[i].$1, steps[i].$2),
                            ),
                          const SizedBox(height: 32),
                          FadeSlideIn(
                            delay: Duration(milliseconds: 140 + steps.length * 60),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Required Documents', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                ..._requiredPermits.map(
                                  (p) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const Icon(Icons.description_outlined, color: AppColors.primary),
                                      title: Text(p.$1),
                                      subtitle: Text(p.$2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                HoverScale(
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                                    child: Text(t('for_owners_cta'), style: const TextStyle(color: Colors.white)),
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

  Widget _stepTile(int number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.grey, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
