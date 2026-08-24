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
  final OrderStatus status;
  final String paymentMethod;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final String? customerPhone;
  final int? emptyJugsReturned;
  final bool? paymentCollected;
  final DateTime createdAt;

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
    required this.status,
    required this.paymentMethod,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalAmount,
    this.customerPhone,
    this.emptyJugsReturned,
    this.paymentCollected,
    required this.createdAt,
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
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      subtotal: (map['subtotal'] as num).toDouble(),
      deliveryFee: (map['delivery_fee'] as num).toDouble(),
      totalAmount: (map['total_amount'] as num).toDouble(),
      customerPhone: map['customer_phone'] as String?,
      emptyJugsReturned: map['empty_jugs_returned'] as int?,
      paymentCollected: map['payment_collected'] as bool?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Result row from the lookup_guest_order() RPC (0008_bulletin.sql) --
/// deliberately a narrower summary than [Order] (no delivery coordinates,
/// no other-customer fields), since a guest-phone-verified lookup is meant
/// to answer "where's my order," not expose the full row.
class GuestOrderStatus {
  final String id;
  final String stationName;
  final OrderStatus status;
  final int jugsOrdered;
  final String waterType;
  final double totalAmount;
  final DateTime createdAt;

  const GuestOrderStatus({
    required this.id,
    required this.stationName,
    required this.status,
    required this.jugsOrdered,
    required this.waterType,
    required this.totalAmount,
    required this.createdAt,
  });

  factory GuestOrderStatus.fromMap(Map<String, dynamic> map) {
    return GuestOrderStatus(
      id: map['id'] as String,
      stationName: map['station_name'] as String,
      status: orderStatusFromString(map['status'] as String? ?? 'pending'),
      jugsOrdered: map['jugs_ordered'] as int,
      waterType: map['water_type'] as String? ?? 'purified',
      totalAmount: (map['total_amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
