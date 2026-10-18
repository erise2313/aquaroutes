import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'portal/portal.dart';

/// The owner's mentor station, or the new stations they mentor, with the
/// other owner's name and a call button (my_mentor_pairs,
/// patch_stations_members.sql). Shows nothing when there's no pairing, or
/// if it can't load -- it's help, not something to block the dashboard on.
class MentorPairsCard extends StatefulWidget {
  const MentorPairsCard({super.key, this.bottomGap = 0});

  /// Space after the card, only when it shows.
  final double bottomGap;

  @override
  State<MentorPairsCard> createState() => _MentorPairsCardState();
}

class _MentorPairsCardState extends State<MentorPairsCard> {
  List<Map<String, dynamic>> _pairs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client.rpc('my_mentor_pairs');
      if (mounted) setState(() => _pairs = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_pairs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomGap),
      child: PortalCard(
        lift: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.handshake_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text('Mentoring', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 4),
            for (final p in _pairs)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        p['relation'] == 'mentor'
                            ? 'Your mentor: ${p['station_name']}${p['owner_name'] != null ? ' (${p['owner_name']})' : ''}'
                            : 'You are mentoring ${p['station_name']}${p['owner_name'] != null ? ' (${p['owner_name']})' : ''}',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    if ((p['owner_phone'] as String?)?.isNotEmpty ?? false)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: p['owner_phone'] as String)),
                        icon: const Icon(Icons.call_outlined),
                        label: Text('Call ${p['owner_phone']}'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
