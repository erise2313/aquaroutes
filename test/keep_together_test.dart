import 'package:aquaroute/utils/keep_together.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keepTogether joins each hyphen to the next part', () {
    expect(keepTogether('GW-STN-2026-0001'), 'GW-⁠STN-⁠2026-⁠0001');
  });

  test('keepTogether leaves the visible text unchanged', () {
    expect(keepTogether('GW-WRK-2026-0008').replaceAll('⁠', ''), 'GW-WRK-2026-0008');
    expect(keepTogether('BUENAV1'), 'BUENAV1');
  });
}
