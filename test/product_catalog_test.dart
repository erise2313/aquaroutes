import 'package:aquaroute/models/bulletin.dart';
import 'package:aquaroute/models/order.dart';
import 'package:aquaroute/models/product.dart';
import 'package:aquaroute/screens/admin/bulletin_editor_screen.dart';
import 'package:aquaroute/screens/merchant/products_screen.dart';
import 'package:aquaroute/screens/public/quick_order_screen.dart';
import 'package:flutter_test/flutter_test.dart';

const _slim = ContainerType(code: 'slim_5gal', label: 'Slim 5-gal', volumeMl: 18900, isReturnable: true, ledgerJugType: 'slim_5gal', sortOrder: 10, isActive: true);
const _round = ContainerType(code: 'round_5gal', label: 'Round 5-gal', volumeMl: 18900, isReturnable: true, ledgerJugType: 'round_5gal', sortOrder: 20, isActive: true);
const _bottle = ContainerType(code: 'bottle_500ml', label: '500 mL bottle', volumeMl: 500, isReturnable: false, sortOrder: 40, isActive: true);
final _containers = {for (final c in [_slim, _round, _bottle]) c.code: c};

StationProduct _product(String id, String water, String container, {ProductKind kind = ProductKind.refill, double price = 25, bool available = true}) =>
    StationProduct(id: id, stationId: 's1', waterType: water, containerCode: container, kind: kind, price: price, isAvailable: available);

void main() {
  group('describeOrderLine', () {
    test('names the container and whether it is a refill', () {
      expect(describeOrderLine(quantity: 3, waterType: 'purified', containerCode: 'slim_5gal', productKind: 'refill'), '3 × Slim 5-gal refill · Purified');
      expect(describeOrderLine(quantity: 2, waterType: 'mineral', containerCode: 'bottle_500ml', productKind: 'new_container'), '2 × 500 mL bottle (new) · Mineral');
    });

    test('prefers the server label, so admin-added containers read properly', () {
      expect(
        describeOrderLine(quantity: 1, waterType: 'alkaline', containerCode: 'bottle_1l', containerLabelOverride: '1-liter bottle', productKind: 'refill'),
        '1 × 1-liter bottle refill · Alkaline',
      );
    });

    test('orders from before the catalog still describe themselves', () {
      expect(describeOrderLine(quantity: 4, waterType: 'purified', containerCode: 'round_5gal'), '4 × Round 5-gal · Purified');
      expect(describeOrderLine(quantity: 4, waterType: 'purified'), '4 × Purified');
    });
  });

  group('expectsEmptyContainers', () {
    test('only refills of returnable containers bring back an empty', () {
      expect(expectsEmptyContainers(productKind: 'refill', containerCode: 'slim_5gal', isReturnable: true), isTrue);
      expect(expectsEmptyContainers(productKind: 'new_container', containerCode: 'slim_5gal', isReturnable: true), isFalse);
      expect(expectsEmptyContainers(productKind: 'refill', containerCode: 'bottle_500ml', isReturnable: false), isFalse);
    });

    test('legacy orders (no kind, 5-gal or no container) count as jug refills', () {
      expect(expectsEmptyContainers(containerCode: 'round_5gal'), isTrue);
      expect(expectsEmptyContainers(), isTrue);
      expect(expectsEmptyContainers(containerCode: 'bottle_500ml'), isFalse);
    });
  });

  group('previewOrderPrice', () {
    test('quantity × unit price plus delivery', () {
      final preview = previewOrderPrice(unitPrice: 22, quantity: 3, deliveryFee: 15);
      expect(preview.subtotal, 66);
      expect(preview.total, 81);
    });

    test('a negative quantity never produces a negative price', () {
      expect(previewOrderPrice(unitPrice: 22, quantity: -2, deliveryFee: 15).total, 15);
    });
  });

  test('groupProductsByWaterType follows water, container, then refill-before-new order', () {
    final grouped = groupProductsByWaterType([
      _product('a', 'mineral', 'round_5gal'),
      _product('b', 'purified', 'bottle_500ml', kind: ProductKind.newContainer),
      _product('c', 'purified', 'round_5gal'),
      _product('d', 'purified', 'slim_5gal', kind: ProductKind.newContainer),
      _product('e', 'purified', 'slim_5gal'),
    ], _containers);
    expect(grouped.keys, ['purified', 'mineral']);
    expect(grouped['purified']!.map((p) => p.id), ['e', 'd', 'c', 'b']);
  });

  test('orderableProducts hides unavailable products, retired containers and other water types', () {
    final products = [
      _product('ok', 'purified', 'slim_5gal'),
      _product('hidden', 'purified', 'round_5gal', available: false),
      _product('retired', 'purified', 'gallon_1'),
      _product('mineral', 'mineral', 'slim_5gal'),
    ];
    expect(orderableProducts(products, _containers).map((p) => p.id), ['ok', 'mineral']);
    expect(orderableProducts(products, _containers, waterType: 'purified').map((p) => p.id), ['ok']);
  });

  group('owner product form', () {
    test('validateProductPrice', () {
      expect(validateProductPrice(''), isNotNull);
      expect(validateProductPrice('abc'), isNotNull);
      expect(validateProductPrice('0'), isNotNull);
      expect(validateProductPrice('25'), isNull);
      expect(validateProductPrice('20', floor: 22), contains('minimum'));
      expect(validateProductPrice('22', floor: 22), isNull);
    });

    test('validateDeliveryFee allows free delivery but not negative', () {
      expect(validateDeliveryFee('0'), isNull);
      expect(validateDeliveryFee('15'), isNull);
      expect(validateDeliveryFee('-1'), isNotNull);
      expect(validateDeliveryFee(''), isNotNull);
    });

    test('isDuplicateProduct matches water type, container and kind, except the one being edited', () {
      final products = [_product('a', 'purified', 'slim_5gal')];
      expect(isDuplicateProduct(products, waterType: 'purified', containerCode: 'slim_5gal', kind: ProductKind.refill), isTrue);
      expect(isDuplicateProduct(products, waterType: 'purified', containerCode: 'slim_5gal', kind: ProductKind.newContainer), isFalse);
      expect(isDuplicateProduct(products, waterType: 'purified', containerCode: 'slim_5gal', kind: ProductKind.refill, exceptId: 'a'), isFalse);
    });

    test('productTitle', () {
      expect(productTitle(_product('a', 'purified', 'slim_5gal'), _slim), 'Slim 5-gal refill');
      expect(productTitle(_product('a', 'purified', 'bottle_500ml', kind: ProductKind.newContainer), _bottle), '500 mL bottle (new container)');
      expect(productTitle(_product('a', 'purified', 'bottle_1l'), null), 'bottle_1l refill');
    });
  });

  test('floorPriceFor is per water type and container', () {
    final floors = [
      FloorPrice(id: '1', waterType: 'purified', containerCode: 'slim_5gal', minPricePerJug: 25, effectiveDate: DateTime(2026, 9, 1)),
      FloorPrice(id: '2', waterType: 'purified', containerCode: 'round_5gal', minPricePerJug: 30, effectiveDate: DateTime(2026, 9, 1)),
    ];
    expect(floorPriceFor(floors, 'purified', 'round_5gal'), 30);
    expect(floorPriceFor(floors, 'purified', 'bottle_500ml'), isNull);
    expect(floorPriceFor(floors, 'mineral', 'slim_5gal'), isNull);
  });

  test('validateContainerCode', () {
    expect(validateContainerCode('bottle_1l'), isNull);
    expect(validateContainerCode(''), isNotNull);
    expect(validateContainerCode('Bottle 1L'), isNotNull);
    expect(validateContainerCode('x'), isNotNull);
  });
}
