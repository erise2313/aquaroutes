import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/screens/trash/trash_screen.dart';
import 'package:aquaroute/widgets/trash_note.dart';

/// The Trash (patch_trash.sql): what people are told about how long a
/// deleted thing waits.
void main() {
  final now = DateTime(2026, 10, 18, 15);

  test('counts whole days to removal', () {
    expect(trashCountdown(DateTime(2026, 10, 23, 9), now: now), 'Removed for good in 5 days');
    expect(trashCountdown(DateTime(2026, 10, 19, 1), now: now), 'Removed for good tomorrow');
    expect(trashCountdown(DateTime(2026, 10, 18, 23), now: now), 'Removed for good today');
    expect(trashCountdown(DateTime(2026, 10, 17), now: now), 'Removed for good today');
  });

  test('every delete confirmation names the same retention as the database', () {
    expect(trashRetentionDays, 5);
    expect(trashNote, contains('5 days'));
  });
}
