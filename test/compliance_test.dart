import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/station_standing.dart';
import 'package:aquaroute/screens/admin/admin_cases_screen.dart';

/// Compliance (UI/Roles plan Phase 3): every standing reads in words and an
/// icon, and no case can be about price.
void main() {
  test('every standing has its own word and icon', () {
    final looks = StationStanding.values.map(StandingLook.of).toList();
    expect(looks.map((l) => l.label).toSet().length, StationStanding.values.length);
    expect(looks.map((l) => l.icon).toSet().length, StationStanding.values.length);
    for (final l in looks) {
      expect(l.explanation, isNotEmpty);
    }
  });

  test('standing reads back from the database, unknown as applicant', () {
    expect(stationStandingFromString('lapsed'), StationStanding.lapsed);
    expect(stationStandingFromString('good'), StationStanding.good);
    expect(stationStandingFromString(null), StationStanding.applicant);
  });

  test('cases are about safety and conduct, never price', () {
    expect(caseKindLabels.keys, isNot(contains('price')));
    expect(caseKindLabels.keys.toSet(), {'permit', 'water_test', 'conduct', 'complaint'});
  });
}
