import 'package:flutter/material.dart';

import '../../models/membership.dart';
import '../../widgets/portal/portal.dart';
import '../public/info/contact_info_screen.dart';
import 'first_run_tour.dart';
import 'help_content.dart';

/// Answers for the signed-in role, the association's contact details, and
/// the first-run tour again.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: density.pagePadding,
        children: [
          PortalSection(
            title: 'Common questions',
            child: PortalCard(
              lift: false,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final q in helpQuestionsFor(role))
                    ExpansionTile(
                      title: Text(q.question, style: theme.textTheme.titleMedium),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(q.answer, style: theme.textTheme.bodyLarge)],
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: density.sectionGap),
          PortalSection(
            title: 'Still stuck?',
            child: Column(
              children: [
                PortalCard(
                  margin: EdgeInsets.only(bottom: density.gap),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactInfoScreen())),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent, color: theme.colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(child: Text('Contact the association office', style: theme.textTheme.titleMedium)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
                PortalCard(
                  onTap: () => showFirstRunTour(context, role, force: true),
                  child: Row(
                    children: [
                      Icon(Icons.replay, color: theme.colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(child: Text('Show the welcome tour again', style: theme.textTheme.titleMedium)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
