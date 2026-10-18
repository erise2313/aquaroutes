import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/membership.dart';
import 'package:aquaroute/screens/admin/admin_orders_screen.dart';
import 'package:aquaroute/screens/admin/admin_reviews_screen.dart';
import 'package:aquaroute/screens/admin/user_management_screen.dart';

/// The matching rules behind the admin sections added for the gaps found on
/// 18 October 2026: Orders, Reviews, and the Users list now covering every
/// role.
void main() {
  group('filterAdminOrders', () {
    final now = DateTime.utc(2026, 10, 18, 12);
    final rows = <Map<String, dynamic>>[
      {
        'id': 'aaaaaaaa-1111-2222-3333-444444444444',
        'status': 'pending',
        'created_at': '2026-10-18T08:00:00Z',
        'customer_phone': '09171234567',
        'customer_name': 'Maria Santos',
        'has_report': true,
        'station_name': 'Buenavista Water',
      },
      {
        'id': 'bbbbbbbb-1111-2222-3333-444444444444',
        'status': 'done',
        'created_at': '2026-09-01T08:00:00Z',
        // No report on file: admin_list_orders leaves the customer out.
        'customer_name': null,
        'customer_phone': null,
        'has_report': false,
        'station_name': 'Navarro Springs',
      },
    ];

    test('no filters keeps everything', () {
      expect(filterAdminOrders(rows, now: now).length, 2);
    });

    test('status narrows', () {
      expect(filterAdminOrders(rows, status: 'done', now: now).single['id'], startsWith('bbbbbbbb'));
    });

    test('age narrows by when the order was placed', () {
      expect(filterAdminOrders(rows, withinDays: 7, now: now).single['id'], startsWith('aaaaaaaa'));
      expect(filterAdminOrders(rows, withinDays: 1, now: now).length, 1);
    });

    test('search matches station, order number, and identity only where shown', () {
      expect(filterAdminOrders(rows, query: 'maria').length, 1);
      expect(filterAdminOrders(rows, query: '0917123').length, 1);
      expect(filterAdminOrders(rows, query: 'navarro').length, 1);
      expect(filterAdminOrders(rows, query: 'AAAAAA').length, 1);
      // The "Hidden" placeholder is not something to search by.
      expect(filterAdminOrders(rows, query: 'hidden'), isEmpty);
    });

    test('identity is shown only for an order with a report', () {
      expect(adminOrderCustomerName(rows[0]), 'Maria Santos');
      expect(adminOrderCustomerName(rows[1]), adminOrderHiddenCustomer);
      expect(adminOrderCustomerPhone(rows[0]), '09171234567');
      expect(adminOrderCustomerPhone(rows[1]), isNull);
      expect(adminOrderNumber(rows[0]), '#AAAAAA');
      expect(adminOrderCustomerName(<String, dynamic>{'has_report': true}), 'Customer');
    });

    test('a row with a broken date is dropped from an age filter, not crashed on', () {
      final broken = [<String, dynamic>{'id': 'cccccccc-0000', 'status': 'pending', 'created_at': 'not a date'}];
      expect(filterAdminOrders(broken, withinDays: 7, now: now), isEmpty);
      expect(filterAdminOrders(broken, now: now).length, 1);
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
