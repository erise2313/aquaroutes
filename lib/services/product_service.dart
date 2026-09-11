import '../models/product.dart';
import 'supabase_service.dart';

/// Station product catalog and the association's container list
/// (supabase/patch_product_catalog.sql).
///
/// Access is enforced by RLS, not by this class: the public can read the
/// products of publicly listed stations, owners manage only their own
/// station's, and only WASA admins edit the container list.
class ProductService {
  ProductService(this._supabase);

  final SupabaseService _supabase;

  Future<List<ContainerType>> fetchContainerTypes({bool includeInactive = false}) async {
    var query = _supabase.client.from('container_types').select();
    if (!includeInactive) query = query.eq('is_active', true);
    final rows = await query.order('sort_order');
    return rows.map((r) => ContainerType.fromMap(r)).toList();
  }

  Future<List<StationProduct>> fetchStationProducts(String stationId) async {
    final rows = await _supabase.client.from('station_products').select().eq('station_id', stationId);
    return rows.map((r) => StationProduct.fromMap(r)).toList();
  }

  /// Creates a product, or updates it in place when [id] is given. The
  /// database enforces floor prices and the one-product-per-combination
  /// rule; their error messages are written to be shown to the owner.
  Future<void> saveProduct({
    String? id,
    required String stationId,
    required String waterType,
    required String containerCode,
    required ProductKind kind,
    required double price,
    required bool isAvailable,
  }) {
    final data = {
      'station_id': stationId,
      'water_type': waterType,
      'container_code': containerCode,
      'kind': productKindToString(kind),
      'price': price,
      'is_available': isAvailable,
    };
    if (id != null) {
      return _supabase.client.from('station_products').update(data).eq('id', id);
    }
    return _supabase.client.from('station_products').insert(data);
  }

  Future<void> setAvailability(String productId, bool isAvailable) {
    return _supabase.client.from('station_products').update({'is_available': isAvailable}).eq('id', productId);
  }

  Future<void> deleteProduct(String productId) {
    return _supabase.client.from('station_products').delete().eq('id', productId);
  }

  Future<double> fetchDeliveryFee(String stationId) async {
    final row = await _supabase.client.from('water_stations').select('delivery_fee').eq('id', stationId).single();
    return (row['delivery_fee'] as num).toDouble();
  }

  Future<void> updateDeliveryFee(String stationId, double fee) {
    return _supabase.client.from('water_stations').update({'delivery_fee': fee}).eq('id', stationId);
  }

  // -- Admin: the association's container list --------------------------

  Future<void> saveContainerType({
    required String code,
    required String label,
    required int volumeMl,
    required bool isReturnable,
    required int sortOrder,
    required bool isActive,
  }) {
    return _supabase.client.from('container_types').upsert({
      'code': code,
      'label': label,
      'volume_ml': volumeMl,
      'is_returnable': isReturnable,
      'sort_order': sortOrder,
      'is_active': isActive,
    }, onConflict: 'code');
  }
}
