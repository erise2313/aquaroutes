import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../providers/web_locale_provider.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Content-only explainer for the jug clearinghouse -- a genuine
/// differentiator no comparable chamber/AMS site template has, so it earns
/// its own page. Mechanics described here are pulled from the real
/// implementation (jug_ledger_service.dart / jug_ledger_entries /
/// jug_balances / propose-confirm-reject settlement RPCs), not invented.
class JugClearinghouseExplainerScreen extends ConsumerStatefulWidget {
  const JugClearinghouseExplainerScreen({super.key});

  @override
  ConsumerState<JugClearinghouseExplainerScreen> createState() => _JugClearinghouseExplainerScreenState();
}

class _JugClearinghouseExplainerScreenState extends ConsumerState<JugClearinghouseExplainerScreen> {
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
      ('A jug crosses station lines', 'When a driver picks up a customer\'s empty 5-gallon jug that actually belongs to a different member station\'s brand (Slim or Round), that transfer gets recorded.'),
      ('The ledger tracks who holds what', 'Every cross-station transfer is logged as a ledger entry -- which station now holds the jug, and which station originally owns it.'),
      ('Balances net out automatically', 'Instead of settling jug-by-jug, the system nets all transfers between two stations into a single running balance per jug type.'),
      ('Stations propose and confirm settlement', 'A holder station proposes a settlement to clear its balance; the owner station confirms or rejects it. Confirming atomically posts the offsetting ledger entry, so the balance can\'t drift or be double-counted.'),
    ];

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.jugClearinghouse),
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
                            child: Text(t('jug_clearinghouse_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('jug_clearinghouse_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 120),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                              child: const Text(
                                'Reusable Slim and Round 5-gallon jugs regularly end up at a different station than the one that owns them -- a driver delivers water in one station\'s jug, and picks up an empty jug bearing a competitor\'s brand. Without a shared system, that jug is effectively lost to its owner. The clearinghouse makes those swaps fair and auditable across the whole association.',
                                style: TextStyle(height: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          for (var i = 0; i < steps.length; i++)
                            FadeSlideIn(delay: Duration(milliseconds: 160 + i * 60), child: _buildStep(i + 1, steps[i].$1, steps[i].$2)),
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
          CircleAvatar(radius: 16, backgroundColor: AppColors.primary, child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
