import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/models/officer_role.dart';
import 'package:aquaroute/widgets/officer_can.dart';

void main() {
  group('OfficerRole.fromMembership', () {
    test('a super admin is a super admin whatever officer_role says', () {
      expect(OfficerRole.fromMembership('wasa_superadmin', null), OfficerRole.superadmin);
      expect(OfficerRole.fromMembership('wasa_superadmin', 'viewer'), OfficerRole.superadmin);
    });

    test('an officer takes their stored role', () {
      for (final key in ['officer', 'compliance', 'workforce', 'content', 'viewer']) {
        expect(OfficerRole.fromMembership('wasa_admin', key)!.key, key);
      }
    });

    test('an officer with no stored role is a full officer (accounts made before roles)', () {
      expect(OfficerRole.fromMembership('wasa_admin', null), OfficerRole.officer);
      expect(OfficerRole.fromMembership('wasa_admin', 'nonsense'), OfficerRole.officer);
    });

    test('an officer_role can never make someone a super admin', () {
      expect(OfficerRole.fromMembership('wasa_admin', 'superadmin'), OfficerRole.officer);
    });

    test('non-officers have no officer role', () {
      for (final role in ['station_owner', 'station_staff', 'driver', 'public_consumer', null]) {
        expect(OfficerRole.fromMembership(role, 'officer'), isNull);
      }
    });
  });

  test('every role has a label and a description for the picker', () {
    for (final role in OfficerRole.values) {
      expect(role.label, isNotEmpty);
      expect(role.description, isNotEmpty);
    }
  });

  // Mirrors officer_area_allowed() in patch_officer_roles.sql; the two must
  // agree, or buttons show that the server refuses.
  test('each role may change exactly its own areas', () {
    final expected = {
      // No role changes the clearinghouse: it is between the two stations.
      OfficerRole.superadmin: OfficerArea.values.toSet()..remove(OfficerArea.network),
      OfficerRole.officer: OfficerArea.values.toSet()..removeAll({OfficerArea.settings, OfficerArea.network}),
      OfficerRole.compliance: {OfficerArea.stations},
      OfficerRole.workforce: {OfficerArea.workers},
      OfficerRole.content: {OfficerArea.content},
      OfficerRole.viewer: <OfficerArea>{},
    };
    for (final role in OfficerRole.values) {
      final allowed = {for (final a in OfficerArea.values) if (officerAreaAllowed(role, a)) a};
      expect(allowed, expected[role], reason: role.name);
    }
  });
}
