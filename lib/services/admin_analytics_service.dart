import 'package:supabase_flutter/supabase_flutter.dart';

/// One month's worth of a counted series. [label] is short ("Mar") for axis
/// use; [monthStart] keeps the real date for tooltips and sorting.
class MonthBucket {
  const MonthBucket({required this.monthStart, required this.label, required this.count});

  final DateTime monthStart;
  final String label;
  final int count;
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);

DateTime _addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  // Floor division, not `~/`: `~/` truncates toward zero, so stepping back
  // across a year boundary (total == -1) gave year + 0 instead of year - 1
  // and landed on December of the *wrong* year. Dart's `%` is already
  // non-negative, so only the year needed fixing.
  return DateTime(d.year + (total / 12).floor(), (total % 12) + 1);
}

/// Buckets [dates] into a continuous run of months so a chart shows a real
/// zero month rather than skipping it -- a gap in the axis reads as "no data
/// collected", a plotted zero reads as "nothing happened", and those mean
/// very different things to someone reviewing a backlog.
///
/// [monthsBack] counts backwards from [now] inclusive; use [monthsForward]
/// for a forward-looking runway (permit expiries). Dates outside the window
/// are ignored, so a permit expiring in three years doesn't stretch the axis.
List<MonthBucket> bucketByMonth(
  Iterable<DateTime> dates, {
  int monthsBack = 0,
  int monthsForward = 0,
  DateTime? now,
}) {
  assert(monthsBack > 0 || monthsForward > 0, 'need a window in at least one direction');
  final anchor = _monthStart(now ?? DateTime.now());
  final start = monthsBack > 0 ? _addMonths(anchor, -(monthsBack - 1)) : anchor;
  final span = monthsBack > 0 ? monthsBack : monthsForward;

  final counts = <DateTime, int>{};
  for (var i = 0; i < span; i++) {
    counts[_addMonths(start, i)] = 0;
  }
  for (final date in dates) {
    final key = _monthStart(date);
    if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
  }

  final keys = counts.keys.toList()..sort();
  return keys
      .map((k) => MonthBucket(monthStart: k, label: _monthNames[k.month - 1], count: counts[k]!))
      .toList();
}

/// Everything the admin dashboard's charts need, in one shape.
class AdminAnalytics {
  const AdminAnalytics({
    required this.accreditationMix,
    required this.accreditedTrend,
    required this.reviewThroughput,
    required this.expiryRunway,
    required this.memberGrowth,
    required this.stationsAccreditedWithoutDate,
    required this.approvedPermits,
    required this.approvedPermitsWithExpiry,
  });

  /// accreditation_status -> station count.
  final Map<String, int> accreditationMix;
  final List<MonthBucket> accreditedTrend;
  final List<MonthBucket> reviewThroughput;
  final List<MonthBucket> expiryRunway;
  final List<MonthBucket> memberGrowth;

  /// Stations accredited before `accredited_at` existed. The trend chart
  /// can't place these, so it says so instead of quietly under-reporting.
  final int stationsAccreditedWithoutDate;

  final int approvedPermits;
  final int approvedPermitsWithExpiry;

  /// True when no approved permit carries an expiry date at all. This is the
  /// difference between "nothing expires soon" and "we don't track expiry",
  /// and the dashboard must not show the reassuring version of that.
  bool get expiryUntracked => approvedPermits > 0 && approvedPermitsWithExpiry == 0;
}

/// Reads the dashboard's trend data. Separate from the dashboard widget so
/// the queries stay testable and the screen stays about layout.
class AdminAnalyticsService {
  AdminAnalyticsService(this._client);

  final SupabaseClient _client;

  Future<AdminAnalytics> fetch({DateTime? now}) async {
    // Run together rather than as a waterfall -- these don't depend on each
    // other, and the dashboard already felt slow doing six sequential awaits.
    final results = await Future.wait([
      _client.from('water_stations').select('accreditation_status, is_accredited, accredited_at'),
      _client.from('permits').select('status, reviewed_at, expiry_date'),
      _client.from('memberships').select('created_at'),
    ]);

    final stations = List<Map<String, dynamic>>.from(results[0]);
    final permits = List<Map<String, dynamic>>.from(results[1]);
    final memberships = List<Map<String, dynamic>>.from(results[2]);

    final mix = <String, int>{};
    final accreditedDates = <DateTime>[];
    var accreditedWithoutDate = 0;
    for (final s in stations) {
      final status = (s['accreditation_status'] as String?) ?? 'pending';
      mix[status] = (mix[status] ?? 0) + 1;
      if (s['is_accredited'] == true) {
        final raw = s['accredited_at'] as String?;
        if (raw == null) {
          accreditedWithoutDate++;
        } else {
          accreditedDates.add(DateTime.parse(raw));
        }
      }
    }

    final reviewedDates = <DateTime>[];
    final expiryDates = <DateTime>[];
    var approved = 0;
    var approvedWithExpiry = 0;
    for (final p in permits) {
      final reviewed = p['reviewed_at'] as String?;
      if (reviewed != null) reviewedDates.add(DateTime.parse(reviewed));
      if (p['status'] == 'approved') {
        approved++;
        final expiry = p['expiry_date'] as String?;
        if (expiry != null) {
          approvedWithExpiry++;
          expiryDates.add(DateTime.parse(expiry));
        }
      }
    }

    final memberDates = memberships
        .map((m) => m['created_at'] as String?)
        .whereType<String>()
        .map(DateTime.parse)
        .toList();

    return AdminAnalytics(
      accreditationMix: mix,
      accreditedTrend: bucketByMonth(accreditedDates, monthsBack: 6, now: now),
      reviewThroughput: bucketByMonth(reviewedDates, monthsBack: 6, now: now),
      expiryRunway: bucketByMonth(expiryDates, monthsForward: 6, now: now),
      memberGrowth: bucketByMonth(memberDates, monthsBack: 6, now: now),
      stationsAccreditedWithoutDate: accreditedWithoutDate,
      approvedPermits: approved,
      approvedPermitsWithExpiry: approvedWithExpiry,
    );
  }
}
