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

  Future<void> updateStatus(String orderId, String newStatus) {
    return _supabase.client.from('orders').update({'status': newStatus}).eq('id', orderId);
  }

  Future<void> assignDriver(String orderId, String workerId) {
    return _supabase.client.from('orders').update({
      'driver_worker_id': workerId,
      'status': 'assigned',
    }).eq('id', orderId);
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
