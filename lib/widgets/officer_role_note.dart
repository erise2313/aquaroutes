import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/membership.dart';
import '../models/officer_role.dart';
import '../providers/app_state.dart';
import 'status_callout.dart';

/// Tells an officer with a limited role what they can change, so a refused
/// save isn't a surprise. Nothing is shown to super admins or full officers.
class OfficerRoleNote extends ConsumerWidget {
  const OfficerRoleNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider).value;
    if (membership == null || membership.role != AppRole.wasaAdmin) return const SizedBox.shrink();
    final role = OfficerRole.fromMembership('wasa_admin', membership.officerRole);
    if (role == null || role == OfficerRole.officer) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: StatusCallout(
        accent: Theme.of(context).colorScheme.primary,
        icon: Icons.badge_outlined,
        title: 'You are signed in as a ${role.label.toLowerCase()}',
        message: role == OfficerRole.viewer
            ? 'You can see everything and export it, but not change anything.'
            : 'You can see everything. You can change: ${role.description[0].toLowerCase()}${role.description.substring(1)}',
      ),
    );
  }
}
