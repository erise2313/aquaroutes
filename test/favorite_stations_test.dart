import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/models/station.dart';
import 'package:aquaroute/services/favorite_station_service.dart';

PublicStation _station(String id, {String? name}) => PublicStation(
  id: id,
  stationName: name ?? 'Station $id',
  stationAddress: 'Somewhere',
  latitude: 14.38,
  longitude: 120.88,
  pricePerJug: 30,
  deliveryFee: 10,
  offeredWaterTypes: const ['purified'],
  isColorumVerified: true,
  isAccredited: true,
  avgRating: 4,
  reviewCount: 2,
  isActive: true,
  offeredJugTypes: const ['slim_5gal'],
  offersJugExchange: false,
  acceptsNewOrders: true,
);

void main() {
  group('FavoriteStationService.pinFavorites', () {
    final a = _station('a');
    final b = _station('b');
    final c = _station('c');

    test('returns the list untouched when nothing is favourited', () {
      final input = [a, b, c];
      expect(FavoriteStationService.pinFavorites(input, {}), same(input));
    });

    test('moves favourites to the front', () {
      final result = FavoriteStationService.pinFavorites([a, b, c], {'c'});
      expect(result.map((s) => s.id), ['c', 'a', 'b']);
    });

    test('keeps the incoming order within each group', () {
      // [a, b, c] is the distance sort; a and c are favourites. a must stay
      // ahead of c because it is nearer, and b keeps its place behind them.
      final result = FavoriteStationService.pinFavorites([a, b, c], {'a', 'c'});
      expect(result.map((s) => s.id), ['a', 'c', 'b']);
    });

    test('is a no-op when every station is a favourite', () {
      final result = FavoriteStationService.pinFavorites([a, b, c], {'a', 'b', 'c'});
      expect(result.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('ignores favourite ids that are not in the list', () {
      // A station can be favourited and then deactivated, which drops it from
      // public_stations while the favourite row survives.
      final result = FavoriteStationService.pinFavorites([a, b], {'zz', 'b'});
      expect(result.map((s) => s.id), ['b', 'a']);
    });

    test('does not mutate the input list', () {
      final input = [a, b, c];
      FavoriteStationService.pinFavorites(input, {'c'});
      expect(input.map((s) => s.id), ['a', 'b', 'c']);
    });
  });
}
