import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/utils/written_address.dart';

void main() {
  group('formatWrittenAddress', () {
    test('joins the parts and puts the landmark last', () {
      expect(
        formatWrittenAddress(street: 'Blk 3 Lot 5, Sampaguita St.', barangay: 'Buenavista I', city: 'General Trias', landmark: 'beside the chapel'),
        'Blk 3 Lot 5, Sampaguita St., Buenavista I, General Trias (Landmark: beside the chapel)',
      );
    });

    test('leaves out blank parts', () {
      expect(formatWrittenAddress(street: '  ', barangay: 'Tejero', city: 'General Trias'), 'Tejero, General Trias');
      expect(formatWrittenAddress(landmark: 'blue gate'), 'Landmark: blue gate');
      expect(formatWrittenAddress(), '');
    });
  });

  group('writtenAddressProblem', () {
    test('needs a street and a barangay', () {
      expect(writtenAddressProblem(street: '', barangay: 'Tejero'), isNotNull);
      expect(writtenAddressProblem(street: 'Blk 3 Lot 5', barangay: null), isNotNull);
      expect(writtenAddressProblem(street: 'Blk 3 Lot 5', barangay: 'Tejero'), isNull);
    });
  });
}
