import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/services/admin_analytics_service.dart';

void main() {
  // Mid-month anchor on purpose: bucketing must key off the month, not off
  // "30 days ago", or the current month drops half its rows.
  final now = DateTime(2026, 9, 15);

  group('bucketByMonth - backward window', () {
    test('returns exactly the requested number of months, oldest first', () {
      final buckets = bucketByMonth([], monthsBack: 6, now: now);
      expect(buckets.length, 6);
      expect(buckets.first.monthStart, DateTime(2026, 4));
      expect(buckets.last.monthStart, DateTime(2026, 9));
      expect(buckets.map((b) => b.label), ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']);
    });

    // A gap in the axis reads as "no data collected"; a plotted zero reads as
    // "nothing happened". They mean different things to someone reviewing a
    // backlog, so empty months must still appear.
    test('keeps empty months as explicit zeros', () {
      final buckets = bucketByMonth([DateTime(2026, 9, 2)], monthsBack: 3, now: now);
      expect(buckets.map((b) => b.count), [0, 0, 1]);
    });

    test('counts multiple dates landing in the same month', () {
      final buckets = bucketByMonth(
        [DateTime(2026, 8, 1), DateTime(2026, 8, 28), DateTime(2026, 9, 3)],
        monthsBack: 3,
        now: now,
      );
      expect(buckets.map((b) => b.count), [0, 2, 1]);
    });

    test('ignores dates outside the window instead of stretching the axis', () {
      final buckets = bucketByMonth(
        [DateTime(2023, 1, 1), DateTime(2030, 1, 1), DateTime(2026, 9, 9)],
        monthsBack: 3,
        now: now,
      );
      expect(buckets.length, 3);
      expect(buckets.map((b) => b.count).reduce((a, b) => a + b), 1);
    });

    test('crosses a year boundary correctly', () {
      final buckets = bucketByMonth([DateTime(2025, 12, 5)], monthsBack: 3, now: DateTime(2026, 2, 10));
      expect(buckets.map((b) => b.label), ['Dec', 'Jan', 'Feb']);
      expect(buckets.first.monthStart, DateTime(2025, 12));
      expect(buckets.map((b) => b.count), [1, 0, 0]);
    });
  });

  group('bucketByMonth - forward window (expiry runway)', () {
    test('starts at the current month and runs forward', () {
      final buckets = bucketByMonth([], monthsForward: 6, now: now);
      expect(buckets.first.monthStart, DateTime(2026, 9));
      expect(buckets.last.monthStart, DateTime(2027, 2));
      expect(buckets.map((b) => b.label), ['Sep', 'Oct', 'Nov', 'Dec', 'Jan', 'Feb']);
    });

    test('counts an upcoming expiry into the right month', () {
      final buckets = bucketByMonth([DateTime(2026, 11, 20)], monthsForward: 6, now: now);
      expect(buckets[2].label, 'Nov');
      expect(buckets[2].count, 1);
    });

    test('ignores already-expired dates, which belong in a backlog not a runway', () {
      final buckets = bucketByMonth([DateTime(2026, 1, 1)], monthsForward: 6, now: now);
      expect(buckets.every((b) => b.count == 0), isTrue);
    });
  });

  group('AdminAnalytics.expiryUntracked', () {
    AdminAnalytics build({required int approved, required int withExpiry}) => AdminAnalytics(
          accreditationMix: const {},
          accreditedTrend: const [],
          reviewThroughput: const [],
          expiryRunway: const [],
          memberGrowth: const [],
          stationsAccreditedWithoutDate: 0,
          approvedPermits: approved,
          approvedPermitsWithExpiry: withExpiry,
        );

    // The live database is in exactly this state: 6 approved permits, not one
    // with an expiry date. "0 expiring soon" would read as reassurance when
    // it actually means nobody is recording expiry at all.
    test('flags approved permits that carry no expiry dates', () {
      expect(build(approved: 6, withExpiry: 0).expiryUntracked, isTrue);
    });

    test('is false once any expiry date is recorded', () {
      expect(build(approved: 6, withExpiry: 1).expiryUntracked, isFalse);
    });

    test('is false when there are no approved permits to track', () {
      expect(build(approved: 0, withExpiry: 0).expiryUntracked, isFalse);
    });
  });
}
