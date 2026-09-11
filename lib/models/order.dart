/// Mirrors the `orders` table (supabase/migrations/0006_orders_driver_state.sql).
///
/// `delivery_location` is a PostGIS `geography(point)` column, which
/// PostgREST does not flatten to lat/lng automatically. Callers must select
/// it as `st_y(delivery_location::geometry) as delivery_lat, st_x(delivery_location::geometry) as delivery_lng`
/// (see OrderService) rather than selecting the raw column.
enum OrderStatus { pending, assigned, active, done, cancelled }

OrderStatus orderStatusFromString(String value) {
  return OrderStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => OrderStatus.pending,
  );
}

/// Display name for a container code ("500 mL bottle"). Covers the starter
/// container list so a screen renders sensibly even without loading
/// `container_types`; a label from the database should win where a screen
/// has one, since the association can rename containers.
String? containerLabel(String? code) {
  switch (code) {
    case 'slim_5gal':
      return 'Slim 5-gal';
    case 'round_5gal':
      return 'Round 5-gal';
    case 'gallon_1':
      return '1-gallon';
    case 'bottle_500ml':
      return '500 mL bottle';
    case 'bottle_350ml':
      return '350 mL bottle';
    default:
      return null;
  }
}

/// Kept for existing callers; containers are no longer only 5-gallon jugs.
String? jugTypeLabel(String? jugType) => containerLabel(jugType);

/// One order line worded for what was actually bought:
/// "3 × Slim 5-gal refill · Purified", "2 × 500 mL bottle (new) · Mineral".
///
/// Replaces "3 jugs of purified", which was wrong for bottles and for buying
/// a new container. Orders placed before the product catalog have no kind,
/// and read as "3 × Slim 5-gal · Purified".
String describeOrderLine({
  required int quantity,
  required String waterType,
  String? containerCode,
  String? containerLabelOverride,
  String? productKind,
}) {
  final water = waterType.isEmpty ? waterType : waterType[0].toUpperCase() + waterType.substring(1);
  final container = containerLabelOverride ?? containerLabel(containerCode);
  if (container == null) return '$quantity × $water';
  final what = switch (productKind) {
    'refill' => '$container refill',
    'new_container' => '$container (new)',
    _ => container,
  };
  return '$quantity × $what · $water';
}

/// Whether a delivery should come back with empty containers: only refills
/// of returnable containers do. A new-container purchase leaves the
/// customer's jug with them, and bottles aren't returned at all.
///
/// Orders from before the catalog have no kind and were always 5-gallon
/// jugs, so a missing container or kind counts as a returnable refill.
bool expectsEmptyContainers({String? productKind, String? containerCode, bool? isReturnable}) {
  final returnable = isReturnable ??
      (containerCode == null || containerCode == 'slim_5gal' || containerCode == 'round_5gal');
  return returnable && (productKind == null || productKind == 'refill');
}

class Order {
  final String id;
  final String stationId;
  final String? customerProfileId;
  final String? guestName;
  final String? guestPhone;
  final String? driverWorkerId;
  final double deliveryLat;
  final double deliveryLng;
  final int jugsOrdered;
  final String waterType;
  final String? jugType;
  final OrderStatus status;
  final String paymentMethod;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final String? customerPhone;
  final int? emptyJugsReturned;
  final bool? paymentCollected;
  final DateTime createdAt;

  /// Snapshot of what was bought, at the price it was bought for. Null on
  /// orders placed before the product catalog.
  final String? productId;
  final double? unitPrice;
  final String? productKind;

  const Order({
    required this.id,
    required this.stationId,
    this.customerProfileId,
    this.guestName,
    this.guestPhone,
    this.driverWorkerId,
    required this.deliveryLat,
    required this.deliveryLng,
    required this.jugsOrdered,
    required this.waterType,
    this.jugType,
    required this.status,
    required this.paymentMethod,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalAmount,
    this.customerPhone,
    this.emptyJugsReturned,
    this.paymentCollected,
    required this.createdAt,
    this.productId,
    this.unitPrice,
    this.productKind,
  });

  String get displayName => guestName ?? customerPhone ?? 'Customer';

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as String,
      stationId: map['station_id'] as String,
      customerProfileId: map['customer_profile_id'] as String?,
      guestName: map['guest_name'] as String?,
      guestPhone: map['guest_phone'] as String?,
      driverWorkerId: map['driver_worker_id'] as String?,
      deliveryLat: (map['delivery_lat'] as num?)?.toDouble() ?? 0,
      deliveryLng: (map['delivery_lng'] as num?)?.toDouble() ?? 0,
      jugsOrdered: map['jugs_ordered'] as int,
      waterType: map['water_type'] as String? ?? 'purified',
      jugType: map['jug_type'] as String?,
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      subtotal: (map['subtotal'] as num).toDouble(),
      deliveryFee: (map['delivery_fee'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      customerPhone: map['customer_phone'] as String?,
      emptyJugsReturned: map['empty_jugs_returned'] as int?,
      paymentCollected: map['payment_collected'] as bool?,
      createdAt: DateTime.parse(map['created_at'] as String),
      productId: map['product_id'] as String?,
      unitPrice: (map['unit_price'] as num?)?.toDouble(),
      productKind: map['product_kind'] as String?,
    );
  }
}

/// Result row from the lookup_guest_order() RPC -- deliberately a narrower
/// summary than [Order] (no delivery coordinates, no other-customer fields),
/// since a guest-phone-verified lookup is meant to answer "where's my
/// order," not expose the full row.
class GuestOrderStatus {
  final String id;
  final String stationName;
  final OrderStatus status;
  final int jugsOrdered;
  final String waterType;
  final String? jugType;
  final double totalAmount;
  final DateTime createdAt;
  final String? containerLabelText;
  final String? productKind;

  const GuestOrderStatus({
    required this.id,
    required this.stationName,
    required this.status,
    required this.jugsOrdered,
    required this.waterType,
    this.jugType,
    required this.totalAmount,
    required this.createdAt,
    this.containerLabelText,
    this.productKind,
  });

  String get lineDescription => describeOrderLine(
        quantity: jugsOrdered,
        waterType: waterType,
        containerCode: jugType,
        containerLabelOverride: containerLabelText,
        productKind: productKind,
      );

  factory GuestOrderStatus.fromMap(Map<String, dynamic> map) {
    return GuestOrderStatus(
      id: map['id'] as String,
      stationName: map['station_name'] as String,
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      jugsOrdered: map['jugs_ordered'] as int,
      waterType: map['water_type'] as String? ?? 'purified',
      jugType: map['jug_type'] as String?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      containerLabelText: map['container_label'] as String?,
      productKind: map['product_kind'] as String?,
    );
  }
}
