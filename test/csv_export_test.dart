import 'package:aquaroute/utils/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCsv', () {
    test('writes a header row and one line per row, CRLF as Excel expects', () {
      final csv = buildCsv(['Name', 'Role'], [
        ['Maria Santos', 'Station Owner'],
        ['Ana Cruz', 'Driver'],
      ]);
      expect(csv, 'Name,Role\r\nMaria Santos,Station Owner\r\nAna Cruz,Driver');
    });

    test('quotes fields containing a comma, and doubles inner quotes', () {
      final csv = buildCsv(['Station', 'Note'], [
        ['Navarro Springs, Inc.', 'said "approved"'],
      ]);
      expect(csv, 'Station,Note\r\n"Navarro Springs, Inc.","said ""approved"""');
    });

    test('quotes fields with line breaks so a row cannot split', () {
      final csv = buildCsv(['Reason'], [
        ['moving\nto Cavite'],
      ]);
      expect(csv, 'Reason\r\n"moving\nto Cavite"');
    });

    test('null and numbers survive, headers alone are valid', () {
      expect(buildCsv(['A', 'B'], [
        [null, 42],
      ]), 'A,B\r\n,42');
      expect(buildCsv(['Only'], const []), 'Only');
    });
  });

  group('csvFileName', () {
    test('is dated and filesystem-safe', () {
      final name = csvFileName('Accreditation status', now: DateTime(2026, 9, 12));
      expect(name, 'gentri-wasa-accreditation-status-2026-09-12.csv');
    });

    test('collapses punctuation rather than emitting it', () {
      final name = csvFileName('Members (all) -- 2026!', now: DateTime(2026, 1, 5));
      expect(name, 'gentri-wasa-members-all-2026-2026-01-05.csv');
    });
  });
}
