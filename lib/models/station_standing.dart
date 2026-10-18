import 'package:flutter/material.dart';

import '../constants/brand_tokens.dart';

/// A station's standing with the association (water_stations.standing,
/// supabase/patch_compliance.sql), worked out the same way for every station
/// by the daily compliance job and on every permit change.
enum StationStanding { applicant, good, warning, lapsed, suspended }

StationStanding stationStandingFromString(String? value) => switch (value) {
      'good' => StationStanding.good,
      'warning' => StationStanding.warning,
      'lapsed' => StationStanding.lapsed,
      'suspended' => StationStanding.suspended,
      _ => StationStanding.applicant,
    };

/// How a standing reads -- in words, a colour and an icon, never colour
/// alone -- to the public, the owner and officers alike.
class StandingLook {
  const StandingLook(this.label, this.color, this.icon, this.explanation);

  final String label;
  final Color color;
  final IconData icon;

  /// One sentence for the owner or a member of the public.
  final String explanation;

  static StandingLook of(StationStanding standing) => switch (standing) {
        StationStanding.good => const StandingLook(
            'GOOD STANDING', BrandStatus.success, Icons.verified_outlined, 'Accredited, with every required permit current.'),
        StationStanding.warning => const StandingLook(
            'RENEWAL DUE', BrandStatus.warning, Icons.schedule,
            'A required permit has expired or is waiting for review. The station is still accredited during the grace period.'),
        StationStanding.lapsed => const StandingLook(
            'LAPSED', BrandStatus.danger, Icons.error_outline,
            'A required permit expired past the grace period, so the Accredited badge is removed until it is renewed.'),
        StationStanding.suspended => const StandingLook(
            'CLOSED', BrandStatus.danger, Icons.block, 'Closed by WASA. Not taking orders.'),
        StationStanding.applicant => const StandingLook(
            'APPLICANT', BrandStatus.info, Icons.hourglass_top, 'Joining the association; permits are being reviewed.'),
      };
}
