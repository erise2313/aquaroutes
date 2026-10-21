/// The city every station is in, and the default for customers.
const kDefaultCity = 'General Trias';

/// One line a driver or customer can read: "Blk 3 Lot 5, Sampaguita St.,
/// Buenavista I, General Trias (Landmark: beside the chapel)". Blank parts are left
/// out. Pure, so it is unit-tested.
String formatWrittenAddress({String? street, String? barangay, String? city, String? landmark}) {
  final parts = [street, barangay, city]
      .map((p) => (p ?? '').trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final line = parts.join(', ');
  final near = (landmark ?? '').trim();
  if (near.isEmpty) return line;
  return line.isEmpty ? 'Landmark: $near' : '$line (Landmark: $near)';
}

/// Why a written address can't be used yet, or null when it's complete
/// enough for someone to find the place: a street (or house/block/lot) and
/// a barangay.
String? writtenAddressProblem({String? street, String? barangay}) {
  if ((street ?? '').trim().length < 3) return 'Enter the house no., street or subdivision';
  if ((barangay ?? '').trim().isEmpty) return 'Choose the barangay';
  return null;
}
