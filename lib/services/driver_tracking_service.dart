import 'supabase_service.dart';

class ActiveDeliveryDriver {
  const ActiveDeliveryDriver({
    required this.driverName,
    required this.driverPhone,
    required this.lat,
    required this.lng,
    required this.lastUpdated,
  });

  final String? driverName;
  final String? driverPhone;
  final double? lat;
  final double? lng;
  final DateTime? lastUpdated;

  bool get hasPosition => lat != null && lng != null;

  factory ActiveDeliveryDriver.fromMap(Map<String, dynamic> map) {
    return ActiveDeliveryDriver(
      driverName: map['driver_name'] as String?,
      driverPhone: map['driver_phone'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      lastUpdated: map['last_updated'] == null ? null : DateTime.parse(map['last_updated'] as String),
    );
  }
}

/// Wraps get_active_delivery_driver(), a security-definer RPC (not RLS) so
/// it authorizes both authenticated customers (auth.uid() match) and guests
/// (phone match) identically -- see supabase/patch_tier1_tier2_features.sql.
class DriverTrackingService {
  DriverTrackingService(this._supabase);

  final SupabaseService _supabase;

  /// Returns null once the order is no longer assigned/active (RPC returns
  /// no rows), or before any driver_states fix has arrived (lat/lng null).
  Future<ActiveDeliveryDriver?> fetchActiveDriver({required String orderId, String? guestPhone}) async {
    final rows = await _supabase.client.rpc('get_active_delivery_driver', params: {
      'p_order_id': orderId,
      'p_guest_phone': guestPhone,
    });
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isEmpty) return null;
    return ActiveDeliveryDriver.fromMap(list.first);
  }
}
