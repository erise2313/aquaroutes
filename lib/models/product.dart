/// A container the association recognises -- mirrors `container_types`
/// (supabase/patch_product_catalog.sql). The association edits this list in
/// admin, so screens should render whatever it contains rather than a
/// hard-coded set of sizes.
class ContainerType {
  const ContainerType({
    required this.code,
    required this.label,
    required this.volumeMl,
    required this.isReturnable,
    this.ledgerJugType,
    required this.sortOrder,
    required this.isActive,
  });

  final String code;
  final String label;
  final int volumeMl;

  /// Returnable containers come back empty on the next delivery; only
  /// refills of these involve an empty-jug exchange.
  final bool isReturnable;

  /// Set only for the containers the jug clearinghouse tracks.
  final String? ledgerJugType;
  final int sortOrder;
  final bool isActive;

  factory ContainerType.fromMap(Map<String, dynamic> map) {
    return ContainerType(
      code: map['code'] as String,
      label: map['label'] as String,
      volumeMl: (map['volume_ml'] as num).toInt(),
      isReturnable: map['is_returnable'] as bool? ?? false,
      ledgerJugType: map['ledger_jug_type'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isActive: map['is_active'] as bool? ?? true,
    );
  }
}

enum ProductKind { refill, newContainer }

ProductKind productKindFromString(String? value) =>
    value == 'new_container' ? ProductKind.newContainer : ProductKind.refill;

String productKindToString(ProductKind kind) =>
    kind == ProductKind.newContainer ? 'new_container' : 'refill';

String productKindLabel(ProductKind kind) =>
    kind == ProductKind.newContainer ? 'New container' : 'Refill';

/// Water types a station can sell, in display order. Mirrors the check
/// constraint on `station_products.water_type`.
const kWaterTypes = ['purified', 'mineral', 'alkaline', 'distilled'];

String waterTypeLabel(String waterType) =>
    waterType.isEmpty ? waterType : waterType[0].toUpperCase() + waterType.substring(1);

/// One thing a station sells -- mirrors `station_products`.
class StationProduct {
  const StationProduct({
    required this.id,
    required this.stationId,
    required this.waterType,
    required this.containerCode,
    required this.kind,
    required this.price,
    required this.isAvailable,
  });

  final String id;
  final String stationId;
  final String waterType;
  final String containerCode;
  final ProductKind kind;
  final double price;
  final bool isAvailable;

  factory StationProduct.fromMap(Map<String, dynamic> map) {
    return StationProduct(
      id: map['id'] as String,
      stationId: map['station_id'] as String,
      waterType: map['water_type'] as String,
      containerCode: map['container_code'] as String,
      kind: productKindFromString(map['kind'] as String?),
      price: (map['price'] as num).toDouble(),
      isAvailable: map['is_available'] as bool? ?? true,
    );
  }
}

/// Products grouped by water type, in [kWaterTypes] order, each group
/// sorted by the association's container order and then refill before new.
/// Water types with no products are omitted.
Map<String, List<StationProduct>> groupProductsByWaterType(
  List<StationProduct> products,
  Map<String, ContainerType> containers,
) {
  int containerOrder(String code) => containers[code]?.sortOrder ?? 1 << 20;

  final grouped = <String, List<StationProduct>>{};
  for (final waterType in kWaterTypes) {
    final group = products.where((p) => p.waterType == waterType).toList()
      ..sort((a, b) {
        final byContainer = containerOrder(a.containerCode).compareTo(containerOrder(b.containerCode));
        if (byContainer != 0) return byContainer;
        return a.kind.index.compareTo(b.kind.index);
      });
    if (group.isNotEmpty) grouped[waterType] = group;
  }
  return grouped;
}

/// What the customer sees before ordering. Display only -- the server
/// computes the amount actually stored on the order.
class OrderPricePreview {
  const OrderPricePreview({required this.subtotal, required this.deliveryFee});

  final double subtotal;
  final double deliveryFee;
  double get total => subtotal + deliveryFee;
}

OrderPricePreview previewOrderPrice({
  required double unitPrice,
  required int quantity,
  required double deliveryFee,
}) {
  final safeQuantity = quantity < 0 ? 0 : quantity;
  return OrderPricePreview(subtotal: unitPrice * safeQuantity, deliveryFee: deliveryFee);
}
