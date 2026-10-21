import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/membership.dart';
import '../models/officer_role.dart';
import '../providers/app_state.dart';

/// The areas an officer role may change. Mirrors officer_area_allowed()
/// in supabase/patch_officer_roles.sql, which is what actually enforces it;
/// this only decides which buttons to show. Pure, so it is unit-tested.
bool officerAreaAllowed(OfficerRole role, OfficerArea area) => switch (role) {
      // The jug clearinghouse is between the two stations; no officer
      // changes it (patch_clearinghouse_appeals.sql).
      _ when area == OfficerArea.network => false,
      OfficerRole.superadmin => true,
      OfficerRole.officer => area != OfficerArea.settings,
      OfficerRole.compliance => area == OfficerArea.stations || area == OfficerArea.network,
      OfficerRole.workforce => area == OfficerArea.workers,
      OfficerRole.content => area == OfficerArea.content,
      OfficerRole.viewer => false,
    };

enum OfficerArea { stations, network, workers, content, accounts, settings }

/// The signed-in officer's role, or null for anyone who isn't an officer.
OfficerRole? currentOfficerRole(WidgetRef ref) {
  final membership = ref.watch(currentMembershipProvider).value;
  if (membership == null || !membership.role.isOfficer) return null;
  return OfficerRole.fromMembership(
    membership.role == AppRole.wasaSuperadmin ? 'wasa_superadmin' : 'wasa_admin',
    membership.officerRole,
  );
}

/// Shows [child] only to officers whose role may change [area]. A Viewer
/// or a Content editor no longer sees buttons that would only be refused
/// by the server. Outside the admin portal (no officer role) it shows the
/// child unchanged, so shared widgets keep working for owners.
class OfficerCan extends ConsumerWidget {
  const OfficerCan({super.key, required this.area, required this.child});

  final OfficerArea area;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = currentOfficerRole(ref);
    if (role == null || officerAreaAllowed(role, area)) return child;
    return const SizedBox.shrink();
  }
}
