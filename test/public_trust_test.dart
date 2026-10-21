import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/station.dart';
import 'package:aquaroute/screens/admin/admin_reports_screen.dart';
import 'package:aquaroute/widgets/station_trust_facts.dart';

PublicStation _station(String id, {bool accredited = true, String? standing, DateTime? accreditedAt, Map<String, dynamic> extra = const {}}) =>
    PublicStation.fromMap({
      'id': id,
      'station_name': 'Station $id',
      'station_address': 'Address',
      'latitude': 14.38,
      'longitude': 120.88,
      'price_per_jug': 25,
      'delivery_fee': 0,
      'is_accredited': accredited,
      'standing': standing,
      'accredited_at': accreditedAt?.toIso8601String(),
      ...extra,
    });

/// Phase 4 (customers and the public): station facts, the customer-facing
/// order of stations, and the officers' report filter.
void main() {
  group('PublicStation association facts', () {
    test('read from public_stations', () {
      final s = _station('a', standing: 'good', extra: {
        'member_since': '2025-03-01T00:00:00Z',
        'last_water_test_at': '2026-09-15T00:00:00Z',
        'sanitary_valid_until': '2027-01-31',
      });
      expect(s.standing, 'good');
      expect(s.memberSince!.year, 2025);
      expect(s.lastWaterTestAt!.month, 9);
      expect(s.sanitaryValidUntil, DateTime(2027, 1, 31));
    });

    test('missing facts stay null rather than failing', () {
      final s = _station('a');
      expect(s.memberSince, isNull);
      expect(s.lastWaterTestAt, isNull);
      expect(s.sanitaryValidUntil, isNull);
    });

    test('new member for 90 days after accreditation, and only while accredited', () {
      final now = DateTime(2026, 10, 18);
      expect(_station('a', accreditedAt: DateTime(2026, 9, 1)).isNewMember(now), isTrue);
      expect(_station('a', accreditedAt: DateTime(2026, 6, 1)).isNewMember(now), isFalse);
      expect(_station('a', accredited: false, accreditedAt: DateTime(2026, 9, 1)).isNewMember(now), isFalse);
      expect(_station('a').isNewMember(now), isFalse);
    });
  });

  group('stationTrustFacts', () {
    final now = DateTime(2026, 10, 18);

    test('says plainly when nothing is on file', () {
      final facts = stationTrustFacts(_station('a'), now: now);
      expect(facts.map((f) => f.value), ['None on file with WASA', 'Not on file with WASA', 'Not recorded']);
    });

    test('shows the station ID and landmark when the station has them', () {
      final facts = stationTrustFacts(
        _station('a', extra: {'station_code': 'GW-STN-2026-0001', 'landmark': 'beside the chapel'}),
        now: now,
      );
      expect(facts.map((f) => f.value), containsAll(['GW-STN-2026-0001', 'beside the chapel']));
    });

    test('a sanitary permit is valid until, or expired on, its date', () {
      final valid = stationTrustFacts(_station('a', extra: {'sanitary_valid_until': '2027-01-31'}), now: now);
      expect(valid[1].value, 'Valid until Jan 31, 2027');
      final expired = stationTrustFacts(_station('a', extra: {'sanitary_valid_until': '2026-10-01'}), now: now);
      expect(expired[1].value, 'Expired Oct 1, 2026');
      // Still valid on its last day.
      final today = stationTrustFacts(_station('a', extra: {'sanitary_valid_until': '2026-10-18'}), now: now);
      expect(today[1].value, startsWith('Valid until'));
    });
  });

  group('orderStationsForCustomers', () {
    test('accredited stations come first', () {
      final ordered = orderStationsForCustomers(
        [_station('x', accredited: false), _station('y'), _station('z', accredited: false), _station('w')],
        today: DateTime(2026, 10, 18),
      );
      expect(ordered.take(2).every((s) => s.isAccredited), isTrue);
      expect(ordered.skip(2).every((s) => !s.isAccredited), isTrue);
    });

    test('then nearest first', () {
      final distances = {'near': 0.4, 'mid': 2.0, 'far': 7.5};
      final ordered = orderStationsForCustomers(
        [_station('far'), _station('near'), _station('mid')],
        distanceKm: (s) => distances[s.id]!,
        today: DateTime(2026, 10, 18),
      );
      expect(ordered.map((s) => s.id), ['near', 'mid', 'far']);
    });

    test('ties are the same all day, and not the same every day', () {
      final stations = [for (var i = 0; i < 8; i++) _station('s$i')];
      final day1 = orderStationsForCustomers(stations, today: DateTime(2026, 10, 18)).map((s) => s.id).toList();
      final day1Again = orderStationsForCustomers(stations.reversed.toList(), today: DateTime(2026, 10, 18, 17)).map((s) => s.id).toList();
      expect(day1Again, day1);
      final otherDays = [
        for (var d = 19; d < 26; d++) orderStationsForCustomers(stations, today: DateTime(2026, 10, d)).map((s) => s.id).join(),
      ];
      expect(otherDays.any((o) => o != day1.join()), isTrue);
    });
  });

  group('filterAdminReports', () {
    final rows = <Map<String, dynamic>>[
      {
        'status': 'new',
        'category': 'cloudy',
        'details': 'Particles in the jug',
        'water_stations': {'station_name': 'Buenavista Water'},
        'profiles': {'full_name': 'Maria Santos'},
      },
      {
        'status': 'reviewing',
        'category': 'driver_conduct',
        'details': 'Rude on delivery',
        'water_stations': {'station_name': 'Navarro Springs'},
        'profiles': null,
      },
      {
        'status': 'resolved',
        'category': 'dirty_jug',
        'details': 'Moss inside',
        'water_stations': {'station_name': 'Navarro Springs'},
        'profiles': {'full_name': 'Ben'},
      },
    ];

    test('"needs attention" is new or reviewing', () {
      expect(filterAdminReports(rows, status: 'open').length, 2);
      expect(filterAdminReports(rows, status: 'resolved').single['details'], 'Moss inside');
      expect(filterAdminReports(rows).length, 3);
    });

    test('search covers station, details, category and reporter', () {
      expect(filterAdminReports(rows, query: 'navarro').length, 2);
      expect(filterAdminReports(rows, query: 'particles').length, 1);
      expect(filterAdminReports(rows, query: 'driver behaviour').length, 1);
      expect(filterAdminReports(rows, query: 'maria').length, 1);
    });
  });
}
