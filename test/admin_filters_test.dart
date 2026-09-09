import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/screens/admin/activity_screen.dart';
import 'package:aquaroute/screens/admin/station_accreditation_screen.dart';
import 'package:aquaroute/screens/admin/user_management_screen.dart';

Map<String, dynamic> _row({
  required String name,
  required String role,
  required String status,
  String? station,
}) =>
    {
      'id': '$name-$role',
      'role': role,
      'status': status,
      'profiles': {'full_name': name},
      'water_stations': station == null ? null : {'station_name': station},
    };

void main() {
  final rows = [
    _row(name: 'Maria Santos', role: 'station_owner', status: 'active', station: 'Aqua Pura'),
    _row(name: 'Jose Rizal', role: 'driver', status: 'active', station: 'Aqua Pura'),
    _row(name: 'Ana Cruz', role: 'driver', status: 'suspended', station: 'Crystal Springs'),
    _row(name: 'Pedro Reyes', role: 'station_owner', status: 'suspended'),
  ];

  group('filterMemberships', () {
    test('returns everything when nothing is set', () {
      expect(filterMemberships(rows).length, 4);
    });

    test('filters by role and by status independently', () {
      expect(filterMemberships(rows, role: 'driver').length, 2);
      expect(filterMemberships(rows, status: 'suspended').length, 2);
    });

    test('combines role and status', () {
      final result = filterMemberships(rows, role: 'driver', status: 'suspended');
      expect(result.length, 1);
      expect(result.single['profiles']['full_name'], 'Ana Cruz');
    });

    test('search matches the person name, case-insensitively', () {
      expect(filterMemberships(rows, query: 'maria').length, 1);
      expect(filterMemberships(rows, query: 'MARIA').length, 1);
    });

    // An admin looking for "who runs Aqua Pura" searches the station, not a
    // person they may not know the name of.
    test('search also matches the station name', () {
      expect(filterMemberships(rows, query: 'aqua pura').length, 2);
    });

    test('tolerates a missing station and a missing profile', () {
      expect(filterMemberships(rows, query: 'pedro').length, 1);
      final broken = [
        {'id': 'x', 'role': 'driver', 'status': 'active', 'profiles': null, 'water_stations': null},
      ];
      expect(filterMemberships(broken, query: 'anything'), isEmpty);
      expect(filterMemberships(broken).length, 1);
    });

    test('whitespace-only search is treated as no search', () {
      expect(filterMemberships(rows, query: '   ').length, 4);
    });
  });

  group('filterStations', () {
    Map<String, dynamic> station(String name, {bool accredited = false, bool active = true, String address = ''}) => {
          'id': name,
          'station_name': name,
          'station_address': address,
          'is_accredited': accredited,
          'is_active': active,
        };

    final stations = [
      station('Aqua Pura', accredited: true, address: 'Barangay Manggahan'),
      station('Crystal Springs', address: 'Barangay Tejero'),
      station('Blue Drop', accredited: true, active: false, address: 'Barangay Manggahan'),
      station('Wellspring', active: false),
    ];

    test('no filter returns everything', () {
      expect(filterStations(stations).length, 4);
    });

    test('accredited excludes a deactivated station even if it is accredited', () {
      final result = filterStations(stations, state: 'accredited');
      expect(result.map((s) => s['station_name']), ['Aqua Pura']);
    });

    // A deactivated station isn't waiting on anyone -- counting it as pending
    // would put work in the review queue that nobody should act on.
    test('pending excludes deactivated stations', () {
      final result = filterStations(stations, state: 'pending');
      expect(result.map((s) => s['station_name']), ['Crystal Springs']);
    });

    test('deactivated returns exactly the inactive ones', () {
      final result = filterStations(stations, state: 'deactivated');
      expect(result.map((s) => s['station_name']), ['Blue Drop', 'Wellspring']);
    });

    test('search matches name or address', () {
      expect(filterStations(stations, query: 'crystal').length, 1);
      expect(filterStations(stations, query: 'manggahan').length, 2);
    });

    test('search and state filter combine', () {
      final result = filterStations(stations, query: 'manggahan', state: 'accredited');
      expect(result.map((s) => s['station_name']), ['Aqua Pura']);
    });

    test('treats missing accredited/active flags as pending and active', () {
      final sparse = [
        {'id': 'x', 'station_name': 'No Flags', 'station_address': null},
      ];
      expect(filterStations(sparse, state: 'pending').length, 1);
      expect(filterStations(sparse, state: 'deactivated'), isEmpty);
    });
  });

  group('filterActivity', () {
    final rows = [
      {'category': 'Permit', 'action': 'Approved permit', 'subject': 'Aqua Pura - business_permit', 'actor_name': 'Maria Santos'},
      {'category': 'Worker credential', 'action': 'Rejected credential for', 'subject': 'Jose Rizal (drivers_license)', 'actor_name': 'Maria Santos'},
      {'category': 'Website content', 'action': 'Edited FAQ', 'subject': 'How do I register?', 'actor_name': 'Ana Cruz'},
    ];

    test('no filter returns everything', () {
      expect(filterActivity(rows).length, 3);
    });

    test('filters by category', () {
      expect(filterActivity(rows, category: 'Permit').length, 1);
    });

    // "What did Maria approve last week" is the question this screen exists
    // to answer, so searching by person has to work.
    test('search matches the actor', () {
      expect(filterActivity(rows, query: 'maria').length, 2);
    });

    test('search matches the subject and the action text', () {
      expect(filterActivity(rows, query: 'aqua pura').length, 1);
      expect(filterActivity(rows, query: 'rejected').length, 1);
    });

    test('category and search combine', () {
      expect(filterActivity(rows, query: 'maria', category: 'Permit').length, 1);
    });

    test('tolerates rows with missing fields', () {
      final sparse = [
        {'category': 'Permit', 'action': null, 'subject': null, 'actor_name': null},
      ];
      expect(filterActivity(sparse).length, 1);
      expect(filterActivity(sparse, query: 'anything'), isEmpty);
    });
  });
}
