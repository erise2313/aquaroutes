import '../utils/written_address.dart';

/// A place a customer orders water to -- mirrors `customer_addresses`
/// (supabase/patch_customer_addresses.sql). Private to the customer; a
/// station only ever sees the delivery point of an order actually placed.
class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    this.notes,
    required this.isDefault,
    this.street,
    this.barangay,
    this.city,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;

  /// Optional landmark or instruction ("blue gate, beside the sari-sari store").
  final String? notes;
  final bool isDefault;

  /// The written address (house no. / street / subdivision, barangay, city)
  /// that goes with the pin. [notes] doubles as the landmark. Null on
  /// addresses saved before these fields existed.
  final String? street;
  final String? barangay;
  final String? city;

  /// "Blk 3 Lot 5, Sampaguita St., Buenavista I, General Trias (Landmark: ...)".
  String get writtenAddress => formatWrittenAddress(street: street, barangay: barangay, city: city, landmark: notes);

  /// Whether a driver could find it from the words alone.
  bool get hasWrittenAddress => writtenAddressProblem(street: street, barangay: barangay) == null;

  factory CustomerAddress.fromMap(Map<String, dynamic> map) {
    return CustomerAddress(
      id: map['id'] as String,
      label: map['label'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      notes: map['notes'] as String?,
      isDefault: map['is_default'] as bool? ?? false,
      street: map['street'] as String?,
      barangay: map['barangay'] as String?,
      city: map['city'] as String?,
    );
  }
}

/// The one to pre-select on the order form: the default, else the first
/// saved, else none. Top-level so the rule is unit-testable.
CustomerAddress? preferredAddress(List<CustomerAddress> addresses) {
  if (addresses.isEmpty) return null;
  for (final address in addresses) {
    if (address.isDefault) return address;
  }
  return addresses.first;
}

String? validateAddressLabel(String? input) {
  final label = input?.trim() ?? '';
  if (label.isEmpty) return 'Give it a name, e.g. Home';
  if (label.length > 40) return 'Keep the name under 40 characters';
  return null;
}
