import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Outstanding work, counted once and shared by whatever needs to display it.
class AdminQueueCounts {
  const AdminQueueCounts({
    required this.pendingPermits,
    required this.pendingIncidents,
    required this.pendingCredentials,
  });

  final int pendingPermits;
  final int pendingIncidents;
  final int pendingCredentials;

  /// Both worker queues live behind the single "Workers" tab, so its badge
  /// has to represent their sum or it would under-report the backlog.
  int get workerQueue => pendingIncidents + pendingCredentials;
}

/// Backlog counts for the admin nav badges.
///
/// Asks Postgres for the counts via `CountOption.exact` rather than pulling
/// the rows down and calling `.length` on them, which is what the screens
/// this feeds were doing.
final adminQueueCountsProvider = FutureProvider.autoDispose<AdminQueueCounts>((ref) async {
  final client = Supabase.instance.client;

  final results = await Future.wait([
    client.from('permits').select('id').eq('status', 'pending_review').count(CountOption.exact),
    client.from('worker_incidents').select('id').eq('status', 'pending_review').count(CountOption.exact),
    client.from('worker_credentials').select('id').eq('status', 'pending_review').count(CountOption.exact),
  ]);

  return AdminQueueCounts(
    pendingPermits: results[0].count,
    pendingIncidents: results[1].count,
    pendingCredentials: results[2].count,
  );
});
