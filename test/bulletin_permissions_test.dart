import 'package:aquaroute/models/bulletin.dart';
import 'package:aquaroute/models/membership.dart';
import 'package:aquaroute/services/bulletin_service.dart';
import 'package:aquaroute/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who may post on the bulletin board.
///
/// This is no longer only the create-post sheet's dropdown: the board's
/// New Post button is shown or hidden on the same answer, so a change here
/// silently changes who sees the button. These lock the policy down.
///
/// Constructing the service is safe without a live backend -- SupabaseService
/// only reaches Supabase.instance.client inside its `client` getter, and
/// allowedCategoriesFor never touches it.
void main() {
  final service = BulletinService(SupabaseService.instance);

  group('allowedCategoriesFor', () {
    test('a signed-in customer may not post, so the New Post button is hidden', () {
      expect(service.allowedCategoriesFor(AppRole.publicConsumer), isEmpty);
    });

    test('a guest may not post either -- their button is a login prompt', () {
      expect(service.allowedCategoriesFor(null), isEmpty);
    });

    test('an admin may post every category', () {
      expect(service.allowedCategoriesFor(AppRole.wasaAdmin), BulletinCategory.values);
    });

    test('a station owner may post events and discussion, but not announcements or price changes', () {
      final allowed = service.allowedCategoriesFor(AppRole.stationOwner);
      expect(allowed, contains(BulletinCategory.event));
      expect(allowed, contains(BulletinCategory.discussion));
      expect(allowed, isNot(contains(BulletinCategory.announcement)));
      expect(allowed, isNot(contains(BulletinCategory.priceChange)));
    });

    test('a driver posts on the same terms as a station owner', () {
      expect(
        service.allowedCategoriesFor(AppRole.driver),
        service.allowedCategoriesFor(AppRole.stationOwner),
      );
    });

    test('only admins may post announcements and price changes', () {
      for (final role in AppRole.values) {
        final allowed = service.allowedCategoriesFor(role);
        final privileged = allowed.contains(BulletinCategory.announcement) ||
            allowed.contains(BulletinCategory.priceChange);
        expect(privileged, role == AppRole.wasaAdmin, reason: 'role: $role');
      }
    });
  });
}
