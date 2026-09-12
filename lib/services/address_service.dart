import '../models/customer_address.dart';
import 'supabase_service.dart';

/// A customer's saved delivery addresses
/// (supabase/patch_customer_addresses.sql). RLS scopes every call to the
/// signed-in customer, and the database keeps "only one default" true.
class AddressService {
  AddressService(this._supabase);

  final SupabaseService _supabase;

  Future<List<CustomerAddress>> fetchAddresses() async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _supabase.client
        .from('customer_addresses')
        .select()
        .eq('profile_id', userId)
        .order('is_default', ascending: false)
        .order('created_at');
    return rows.map(CustomerAddress.fromMap).toList();
  }

  /// Creates, or updates when [id] is given.
  Future<CustomerAddress?> saveAddress({
    String? id,
    required String label,
    required double latitude,
    required double longitude,
    String? notes,
    bool isDefault = false,
  }) async {
    final userId = _supabase.client.auth.currentUser?.id;
    if (userId == null) return null;
    final trimmedNotes = notes?.trim();
    final data = {
      'profile_id': userId,
      'label': label.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'notes': trimmedNotes == null || trimmedNotes.isEmpty ? null : trimmedNotes,
      'is_default': isDefault,
    };
    final rows = id == null
        ? await _supabase.client.from('customer_addresses').insert(data).select()
        : await _supabase.client.from('customer_addresses').update(data).eq('id', id).select();
    return rows.isEmpty ? null : CustomerAddress.fromMap(rows.first);
  }

  Future<void> setDefault(String id) {
    return _supabase.client.from('customer_addresses').update({'is_default': true}).eq('id', id);
  }

  Future<void> deleteAddress(String id) {
    return _supabase.client.from('customer_addresses').delete().eq('id', id);
  }
}
