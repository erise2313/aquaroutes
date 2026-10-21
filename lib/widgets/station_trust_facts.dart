import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/brand_tokens.dart';
import '../models/station.dart';
import '../models/station_standing.dart';
import 'portal/status_pill.dart';

/// One line of a station's association record, as a customer reads it.
typedef StationTrustFact = ({IconData icon, String label, String value});

/// The facts a customer can check before ordering (patch_public_trust.sql's
/// public_stations columns): last passed water test, sanitary permit,
/// and when the station joined. Pure, so it is unit-tested.
List<StationTrustFact> stationTrustFacts(PublicStation station, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final month = DateFormat('MMMM yyyy');
  final day = DateFormat('MMM d, yyyy');
  final sanitary = station.sanitaryValidUntil;
  return [
    (
      icon: Icons.science_outlined,
      label: 'Last passed water test',
      value: station.lastWaterTestAt == null ? 'None on file with WASA' : month.format(station.lastWaterTestAt!),
    ),
    (
      icon: Icons.health_and_safety_outlined,
      label: 'Sanitary permit',
      value: sanitary == null
          ? 'Not on file with WASA'
          : sanitary.isBefore(DateTime(today.year, today.month, today.day))
              ? 'Expired ${day.format(sanitary)}'
              : 'Valid until ${day.format(sanitary)}',
    ),
    (
      icon: Icons.groups_outlined,
      label: 'Member since',
      value: station.memberSince == null ? 'Not recorded' : month.format(station.memberSince!),
    ),
    // Stations can share a name; the ID is the one a complaint or a
    // "Check a station" search can rely on.
    if (station.stationCode != null)
      (icon: Icons.tag, label: 'WASA station ID', value: station.stationCode!),
    if ((station.landmark ?? '').trim().isNotEmpty)
      (icon: Icons.flag_outlined, label: 'Landmark', value: station.landmark!.trim()),
  ];
}

/// The station's standing in a word, a colour and an icon, with a
/// "New member" pill beside it for its first 90 days as accredited.
class StationStandingPills extends StatelessWidget {
  const StationStandingPills({super.key, required this.station});

  final PublicStation station;

  @override
  Widget build(BuildContext context) {
    final look = StandingLook.of(stationStandingFromString(station.standing));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (station.standing != null) StatusPill(label: look.label, color: look.color, icon: look.icon),
        if (station.isNewMember()) const StatusPill(label: 'NEW MEMBER', color: BrandStatus.info, icon: Icons.fiber_new_outlined),
      ],
    );
  }
}

/// Standing pills, the one-sentence explanation, and the facts list --
/// used on the website's station page and the app's station sheet so both
/// say the same thing.
class StationTrustPanel extends StatelessWidget {
  const StationTrustPanel({super.key, required this.station, this.textColor, this.mutedColor});

  final PublicStation station;
  final Color? textColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = textColor ?? theme.colorScheme.onSurface;
    final muted = mutedColor ?? theme.colorScheme.onSurfaceVariant;
    final look = StandingLook.of(stationStandingFromString(station.standing));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StationStandingPills(station: station),
        if (station.standing != null) ...[
          const SizedBox(height: 8),
          Text(look.explanation, style: TextStyle(fontSize: 16, color: muted, height: 1.4)),
        ],
        if (station.isNewMember()) ...[
          const SizedBox(height: 4),
          Text('Joined the association recently -- new, not unknown.', style: TextStyle(fontSize: 16, color: muted, height: 1.4)),
        ],
        const SizedBox(height: 12),
        for (final fact in stationTrustFacts(station))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(fact.icon, size: 22, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${fact.label}: ', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                      TextSpan(text: fact.value, style: TextStyle(color: ink)),
                    ]),
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
