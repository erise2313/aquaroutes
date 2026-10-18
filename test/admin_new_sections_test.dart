import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/membership.dart';
import 'package:aquaroute/screens/admin/admin_orders_screen.dart';
import 'package:aquaroute/screens/admin/admin_reviews_screen.dart';
import 'package:aquaroute/screens/admin/user_management_screen.dart';

/// The matching rules behind the admin sections added for the gaps found on
/// 18 October 2026: reported orders, Reviews, and the Users list now covering every
/// role.
void main() {
  group('reported orders', () {
    // Officers reach an order only through a report about it, so every row
    // admin_list_orders returns carries the customer's details.
    final row = <String, dynamic>{
      'id': 'aaaaaaaa-1111-2222-3333-444444444444',
      'customer_phone': '09171234567',
      'customer_name': 'Maria Santos',
    };

    test('name, phone and order number', () {
      expect(adminOrderCustomerName(row), 'Maria Santos');
      expect(adminOrderCustomerPhone(row), '09171234567');
      expect(adminOrderNumber(row), '#AAAAAA');
    });

    test('a missing name falls back to Customer', () {
      expect(adminOrderCustomerName(<String, dynamic>{}), 'Customer');
    });
  });

  group('filterAdminReviews', () {
    final rows = <Map<String, dynamic>>[
      {'rating': 1, 'comment': 'Rude driver', 'water_stations': {'station_name': 'Aqua Pura'}, 'profiles': {'full_name': 'Ana'}},
      {'rating': 3, 'comment': '', 'water_stations': {'station_name': 'Aqua Pura'}, 'profiles': {'full_name': 'Ben'}},
      {'rating': 5, 'comment': null, 'water_stations': {'station_name': 'Navarro'}, 'profiles': null},
    ];

    test('rating bands', () {
      expect(filterAdminReviews(rows, band: 'low').single['rating'], 1);
      expect(filterAdminReviews(rows, band: 'mid').single['rating'], 3);
      expect(filterAdminReviews(rows, band: 'high').single['rating'], 5);
    });

    test('only reviews that say something', () {
      expect(filterAdminReviews(rows, withComment: true).single['rating'], 1);
    });

    test('search matches station, reviewer and comment', () {
      expect(filterAdminReviews(rows, query: 'aqua').length, 2);
      expect(filterAdminReviews(rows, query: 'ben').length, 1);
      expect(filterAdminReviews(rows, query: 'RUDE').length, 1);
      expect(filterAdminReviews(rows, query: 'nobody'), isEmpty);
    });
  });

  group('Users covers every role', () {
    test('each role has a label', () {
      expect(membershipRoleLabel('public_consumer'), 'Customer');
      expect(membershipRoleLabel('wasa_admin'), 'WASA Officer');
      expect(membershipRoleLabel('station_owner'), 'Station Owner');
      expect(membershipRoleLabel('driver'), 'Driver / Helper');
      expect(membershipRoleLabel(null), 'No role');
    });

    test('super admins and station staff read back from the database', () {
      expect(appRoleFromString('wasa_superadmin'), AppRole.wasaSuperadmin);
      expect(appRoleFromString('station_staff'), AppRole.stationStaff);
      for (final role in AppRole.values) {
        expect(appRoleFromString(appRoleToString(role)), role);
      }
      expect(AppRole.wasaSuperadmin.isOfficer, isTrue);
      expect(AppRole.stationStaff.isOfficer, isFalse);
      expect(AppRole.stationStaff.isStationSide, isTrue);
      expect(membershipRoleLabel('wasa_superadmin'), 'WASA Super Admin');
      expect(membershipRoleLabel('station_staff'), 'Station Staff');
    });

    test('a customer can be found by phone number', () {
      final rows = [
        {'role': 'public_consumer', 'status': 'active', 'profiles': {'full_name': 'Carla', 'phone_number': '09175550000'}},
        {'role': 'driver', 'status': 'active', 'profiles': {'full_name': 'Dan', 'phone_number': null}},
      ];
      expect(filterMemberships(rows, query: '0917555').single['role'], 'public_consumer');
      expect(filterMemberships(rows, role: 'public_consumer').length, 1);
    });
  });
}
