/// Most jugs a driver can carry. The database refuses anything outside
/// 1..[kMaxJugCapacity] (patch_quantity_limits.sql); this gives the same
/// answer before the request is sent.
const kMaxJugCapacity = 20;

/// An error for the capacity field, or null when it is fine. Blank is
/// allowed only when [required] is false.
String? jugCapacityError(String? value, {bool required = true}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return required ? 'Enter the jug capacity' : null;
  final n = int.tryParse(text);
  if (n == null) return 'Enter a whole number';
  if (n < 1 || n > kMaxJugCapacity) return 'Between 1 and $kMaxJugCapacity jugs';
  return null;
}
