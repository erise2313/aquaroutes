import '../models/order.dart';
import 'supabase_service.dart';

/// Order queries/mutations, scoped by RLS to the owner's own station, the
/// assigned driver's station, or (for guest inserts) narrowly to
/// customer_profile_id = null rows (supabase/migrations/0009_rls.sql).
///
/// Note: `orders.delivery_location` is a PostGIS geography column;
/// PostgREST won't flatten it automatically, so reads that need lat/lng go
/// through get_active_orders() rather than a raw select here.
class OrderService {
  OrderService(this._supabase);

  final SupabaseService _supabase;

  Stream<List<Map<String, dynamic>>> watchStationOrders(String stationId) {
    return _supabase.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('station_id', stationId)
        .order('created_at', ascending: false);
  }

  /// All status/assignment changes go through set_order_status() (a single
  /// security-definer RPC) instead of raw table updates -- it validates the
  /// transition server-side per caller role (customer/guest, driver, owner/
  /// admin) and locks the row, closing the race conditions and cross-driver
  /// tampering a raw `.update()` from each screen used to allow.
  Future<void> assignDriver(String orderId, String workerId) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'assigned',
      'p_driver_worker_id': workerId,
    });
  }

  Future<void> unassignOrder(String orderId) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'pending',
    });
  }

  Future<void> ownerCancelOrder(String orderId) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'cancelled',
    });
  }

  /// Customer/guest self-cancel -- only valid while the order hasn't gone
  /// out for delivery yet. `guestPhone` authenticates a signed-out caller
  /// the same way lookup_guest_order()/get_active_delivery_driver() do.
  Future<void> cancelOrder({required String orderId, String? guestPhone}) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'cancelled',
      'p_guest_phone': guestPhone,
    });
  }

  Future<void> startDelivery(String orderId) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'active',
    });
  }

  /// [jugExchangeOriginStationId] lets the driver confirm/correct which
  /// station's jug was actually handed back (they're the one looking at
  /// it) -- if omitted, whatever the customer declared at order time is
  /// kept as-is. [noJugExchange] overrides that entirely to "no exchange
  /// happened," in case the customer's order-time declaration turns out
  /// to be wrong at the doorstep. set_order_status writes the resulting
  /// jug_ledger_entries row automatically -- see supabase/patch_jug_provenance.sql.
  Future<void> completeDelivery(
    String orderId, {
    required int emptyJugsReturned,
    required bool paymentCollected,
    String? jugExchangeOriginStationId,
    bool noJugExchange = false,
  }) {
    return _supabase.client.rpc('set_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': 'done',
      'p_empty_jugs_returned': emptyJugsReturned,
      'p_payment_collected': paymentCollected,
      'p_jug_exchange_origin_station_id': jugExchangeOriginStationId,
      'p_no_jug_exchange': noJugExchange,
    });
  }

  Future<String> insertQuickOrder({
    required String stationId,
    required double lat,
    required double lng,
    required int jugsOrdered,
    required String waterType,
    required double subtotal,
    required double deliveryFee,
    required double totalAmount,
    String? guestName,
    String? guestPhone,
    String? clientRequestId,
    DateTime? scheduledFor,
    String? jugType,
    String? jugExchangeOriginStationId,
  }) async {
    final id = await _supabase.client.rpc('insert_quick_order', params: {
      'p_station_id': stationId,
      'p_lat': lat,
      'p_lng': lng,
      'p_jugs_ordered': jugsOrdered,
      'p_water_type': waterType,
      'p_subtotal': subtotal,
      'p_delivery_fee': deliveryFee,
      'p_total_amount': totalAmount,
      'p_guest_name': guestName,
      'p_guest_phone': guestPhone,
      'p_client_request_id': clientRequestId,
      'p_scheduled_for': scheduledFor?.toIso8601String(),
      'p_jug_type': jugType,
      'p_jug_exchange_origin_station_id': jugExchangeOriginStationId,
    });
    return id as String;
  }

  Future<List<Map<String, dynamic>>> fetchActiveOrderPins(String stationId) async {
    final rows = await _supabase.client.rpc('get_active_orders', params: {'p_station_id': stationId});
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Phone-verified guest order lookup -- returns null if the order id and
  /// phone number don't match (see lookup_guest_order() RPC, 0008_bulletin.sql).
  Future<GuestOrderStatus?> lookupGuestOrder({required String orderId, required String guestPhone}) async {
    final rows = await _supabase.client.rpc('lookup_guest_order', params: {
      'p_order_id': orderId,
      'p_guest_phone': guestPhone,
    });
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isEmpty) return null;
    return GuestOrderStatus.fromMap(list.first);
  }
}
