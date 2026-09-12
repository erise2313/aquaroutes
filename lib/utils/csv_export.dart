/// Builds CSV the association can open in Excel or Google Sheets.
///
/// Admin could read every list on screen but never take one to a meeting:
/// there was no export anywhere. Kept as a pure function so the escaping --
/// the part that quietly corrupts a file when it's wrong -- is testable
/// without a browser.
///
/// Follows RFC 4180: fields containing a comma, quote or line break are
/// wrapped in quotes, and quotes inside them are doubled. Rows end with
/// CRLF, which is what Excel expects.
String buildCsv(List<String> headers, List<List<Object?>> rows) {
  final buffer = StringBuffer();
  buffer.write(headers.map(_escapeCsvField).join(','));
  for (final row in rows) {
    buffer.write('\r\n');
    buffer.write(row.map(_escapeCsvField).join(','));
  }
  return buffer.toString();
}

String _escapeCsvField(Object? value) {
  final text = value?.toString() ?? '';
  final needsQuotes = text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r');
  if (!needsQuotes) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// A filename that won't be rejected by a filesystem, stamped with the day
/// it was exported so two downloads don't overwrite each other.
String csvFileName(String base, {DateTime? now}) {
  final date = now ?? DateTime.now();
  final stamp = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final safe = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return 'gentri-wasa-$safe-$stamp.csv';
}
