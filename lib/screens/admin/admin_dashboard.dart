import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_route.dart';
import 'events_admin_screen.dart';
import 'permit_review_screen.dart';
import 'resources_admin_screen.dart';
import 'worker_clearance_screen.dart';
import '../../constants/app_colors.dart';
import '../../constants/admin_theme.dart';
import '../../services/admin_analytics_service.dart';
import '../../widgets/admin_charts.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_seal.dart';
import '../../utils/error_text.dart';
import '../../constants/admin_palette.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

/// One row in the "Needs Your Review" inbox -- a thin merge of pending
/// permits/credentials/incidents into a single sorted list, each tappable
/// straight into the existing review screen for that item. No new review
/// logic here -- purely a unified entry point into screens that already work.
class _ReviewItem {
  final String label;
  final String subtitle;
  final DateTime createdAt;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ReviewItem({
    required this.label,
    required this.subtitle,
    required this.createdAt,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  /// How many review rows the overview shows before deferring to the
  /// dedicated screens. The overview's job is "what needs attention", not
  /// "work the whole queue here".
  static const _reviewItemLimit = 8;

  final _supabase = Supabase.instance.client;
  late final _analyticsService = AdminAnalyticsService(_supabase);
  bool _isLoading = true;
  String? _error;

  int _accreditedCount = 0;
  int _pendingCount = 0;
  int _pendingPermits = 0;
  int _openIncidents = 0;
  int _flaggedWorkers = 0;
  int _expiringSoonPermits = 0;
  AdminAnalytics? _analytics;
  List<_ReviewItem> _reviewItems = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Issued together, not one after another: none of these depends on
      // another's result, and six sequential round-trips made the landing
      // page wait for the sum of them.
      final responses = await Future.wait([
        _supabase.from('water_stations').select('is_accredited'),
        _supabase
            .from('permits')
            .select('id, permit_type, created_at, expiry_date, water_stations(id, station_name)')
            .eq('status', 'pending_review'),
        _supabase
            .from('permits')
            .select('id')
            .eq('status', 'approved')
            .not('expiry_date', 'is', null)
            .lte('expiry_date', DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first),
        _supabase
            .from('worker_incidents')
            .select('id, incident_type, created_at, workers(full_name)')
            .eq('status', 'pending_review'),
        _supabase
            .from('worker_credentials')
            .select('id, credential_type, uploaded_at, workers(full_name)')
            .eq('status', 'pending_review'),
        _supabase.from('workers').select('id').eq('clearance_status', 'flagged'),
      ]);
      final analytics = await _analyticsService.fetch();

      final stations = responses[0];
      final permits = responses[1];
      final expiring = responses[2];
      final incidents = responses[3];
      final credentials = responses[4];
      final flagged = responses[5];

      int accredited = 0, pending = 0;
      for (final s in stations) {
        if (s['is_accredited'] == true) {
          accredited++;
        } else {
          pending++;
        }
      }

      final items = <_ReviewItem>[
        for (final p in permits)
          _ReviewItem(
            label: 'Permit: ${p['permit_type']}',
            subtitle: (p['water_stations']?['station_name'] as String?) ?? 'Unknown station',
            createdAt: DateTime.parse(p['created_at'] as String),
            icon: Icons.description_outlined,
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              adminRoute(
                PermitReviewScreen(
                  stationId: p['water_stations']?['id'] as String? ?? '',
                  stationName: (p['water_stations']?['station_name'] as String?) ?? 'Station',
                ),
              ),
            ).then((_) => _fetchStats()),
          ),
        for (final i in incidents)
          _ReviewItem(
            label: 'Incident: ${i['incident_type']}',
            subtitle: (i['workers']?['full_name'] as String?) ?? 'Unknown worker',
            createdAt: DateTime.parse(i['created_at'] as String),
            icon: Icons.warning_amber_rounded,
            color: Colors.deepOrange,
            onTap: () => Navigator.push(context, adminRoute(const WorkerClearanceScreen(initialTabIndex: 0)))
                .then((_) => _fetchStats()),
          ),
        for (final c in credentials)
          _ReviewItem(
            label: 'Credential: ${c['credential_type']}',
            subtitle: (c['workers']?['full_name'] as String?) ?? 'Unknown worker',
            createdAt: DateTime.parse(c['uploaded_at'] as String? ?? DateTime.now().toIso8601String()),
            icon: Icons.badge_outlined,
            color: Colors.purple,
            onTap: () => Navigator.push(context, adminRoute(const WorkerClearanceScreen(initialTabIndex: 1)))
                .then((_) => _fetchStats()),
          ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _accreditedCount = accredited;
          _pendingCount = pending;
          _pendingPermits = permits.length;
          _openIncidents = incidents.length;
          _flaggedWorkers = flagged.length;
          _expiringSoonPermits = expiring.length;
          _analytics = analytics;
          _reviewItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Never fall through to rendering zeros here: "0 permits to review /
      // 0 open incidents" reads as a genuine all-clear, so a failed load
      // would quietly tell an admin there's nothing to do.
      debugPrint('Error fetching admin stats: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load the overview. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AdminPageHeader(title: 'GENTRI WASA Overview'),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4, cardHeight: 110))
              : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchStats)
              : RefreshIndicator(
              onRefresh: _fetchStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Station accreditation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  // The one loud element on this page -- WASA's actual gold
                  // seal (widgets/web_seal.dart, used everywhere the site
                  // communicates verification) carries the headline number
                  // instead of a generic colored box. Pending sits beside it
                  // as the quieter, secondary figure.
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const WebSeal(size: 64),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Accredited stations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminPalette.of(context).inkMuted)),
                                const SizedBox(height: 4),
                                Text('$_accreditedCount', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: AdminPalette.of(context).ink)),
                              ],
                            ),
                          ),
                          Container(width: 1, height: 52, color: AdminPalette.of(context).border),
                          const SizedBox(width: 18),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pending', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminPalette.of(context).inkMuted)),
                              const SizedBox(height: 4),
                              Text('$_pendingCount', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.pendingClearance)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Needs your attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _kpiTile(icon: Icons.description_outlined, label: 'Permits to review', value: _pendingPermits, color: AdminTheme.harborBlue),
                      _kpiTile(icon: Icons.warning_amber_rounded, label: 'Open incidents', value: _openIncidents, color: Colors.deepOrange),
                      _kpiTile(icon: Icons.flag_outlined, label: 'Flagged workers', value: _flaggedWorkers, color: AppColors.flagged),
                      // When no approved permit carries an expiry date at
                      // all, "0 expiring soon" is not an all-clear -- it means
                      // expiry isn't being tracked. Showing the reassuring
                      // number would be the same silent-zero trap the failed
                      // load above is guarded against.
                      _kpiTile(
                        icon: Icons.hourglass_bottom,
                        label: 'Permits expiring soon',
                        value: _expiringSoonPermits,
                        color: AppColors.pendingClearance,
                        overrideValue: (_analytics?.expiryUntracked ?? false) ? '--' : null,
                        note: (_analytics?.expiryUntracked ?? false) ? 'No expiry dates recorded' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_analytics != null) ...[
                    const Text('Trends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildCharts(_analytics!),
                    const SizedBox(height: 24),
                  ],
                  const Text('Needs Your Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_reviewItems.isEmpty)
                    Text('Nothing pending review right now.', style: TextStyle(color: AdminPalette.of(context).inkMuted))
                  else ...[
                    // Capped: these are spread into the surrounding ListView,
                    // so every row is built eagerly. A large backlog would
                    // build hundreds of tiles before the page could paint.
                    ..._reviewItems.take(_reviewItemLimit).map(_buildReviewItemTile),
                    if (_reviewItems.length > _reviewItemLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Showing the $_reviewItemLimit most recent of ${_reviewItems.length} items awaiting review. '
                          'Open Stations or Workers to work through the rest.',
                          style: TextStyle(color: AdminPalette.of(context).inkMuted, fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  const Text('Content management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0x1A2196F3), child: Icon(Icons.folder_outlined, color: Colors.blue)),
                      title: const Text('Resources Library'),
                      subtitle: const Text('Upload permit checklists, pricing schedules, and other downloads'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.push(context, adminRoute(const ResourcesAdminScreen())),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0x1A3F51B5), child: Icon(Icons.event_outlined, color: Colors.indigo)),
                      title: const Text('Events'),
                      subtitle: const Text('Create and manage upcoming association events'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.push(context, adminRoute(const EventsAdminScreen())),
                    ),
                  ),
                ],
              ),
            ),
        ),
      ],
    );
  }

  Widget _buildReviewItemTile(_ReviewItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: item.color.withValues(alpha: 0.15), child: Icon(item.icon, color: item.color)),
        title: Text(item.label),
        subtitle: Text('${item.subtitle} · ${DateFormat('MMM d, yyyy').format(item.createdAt)}'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: item.onTap,
      ),
    );
  }

  /// Stat-tile contract: icon in a tinted circle (status color lives here,
  /// not as a full-bleed background wash) + sentence-case label + semibold
  /// value, on a white elevated Card. Fixed width inside a Wrap so tiles
  /// reflow by available space instead of being locked to exactly two
  /// per row on every screen size.
  Widget _kpiTile({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    String? overrideValue,
    String? note,
  }) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 21, backgroundColor: color.withValues(alpha: 0.14), child: Icon(icon, color: color, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overrideValue ?? '$value',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AdminPalette.of(context).ink),
                    ),
                    const SizedBox(height: 2),
                    Text(label, style: TextStyle(fontSize: 12.5, color: AdminPalette.of(context).inkMuted, height: 1.2)),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        style: TextStyle(fontSize: 11, height: 1.2, fontStyle: FontStyle.italic, color: AppColors.pendingClearance),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Charts reflow into columns by available width rather than sitting in a
  /// fixed grid -- the portal now runs up to 1440px wide, where a single
  /// stacked column would waste most of the window.
  Widget _buildCharts(AdminAnalytics a) {
    final expiryTotal = a.expiryRunway.fold<int>(0, (s, b) => s + b.count);
    final reviewTotal = a.reviewThroughput.fold<int>(0, (s, b) => s + b.count);
    final accreditedTotal = a.accreditedTrend.fold<int>(0, (s, b) => s + b.count);
    final memberTotal = a.memberGrowth.fold<int>(0, (s, b) => s + b.count);

    final cards = <Widget>[
      AdminChartCard(
        title: 'Permit expiry runway',
        subtitle: 'Approved permits expiring over the next 6 months',
        isEmpty: expiryTotal == 0,
        // The distinction that matters: nothing scheduled to expire, versus
        // nobody recording expiry dates in the first place.
        emptyMessage: a.expiryUntracked
            ? 'None of the ${a.approvedPermits} approved permits has an expiry date recorded, so nothing can be projected. Set expiry dates when approving a permit to populate this.'
            : 'No approved permits expire in the next 6 months.',
        child: AdminMonthBarChart(buckets: a.expiryRunway, color: AppColors.pendingClearance),
      ),
      AdminChartCard(
        title: 'Permits reviewed',
        subtitle: 'Association review activity, last 6 months',
        isEmpty: reviewTotal == 0,
        emptyMessage: 'No permits have been reviewed in the last 6 months.',
        child: AdminMonthBarChart(buckets: a.reviewThroughput),
      ),
      AdminChartCard(
        title: 'Accreditation status',
        subtitle: 'Every registered station, by current status',
        isEmpty: a.accreditationMix.values.every((v) => v == 0),
        emptyMessage: 'No stations registered yet.',
        child: AdminDonutChart(slices: _friendlyMix(a.accreditationMix)),
      ),
      AdminChartCard(
        title: 'Newly accredited stations',
        subtitle: 'Last 6 months',
        isEmpty: accreditedTotal == 0,
        emptyMessage: a.stationsAccreditedWithoutDate > 0
            ? 'No stations were accredited in the last 6 months.'
            : 'No stations accredited yet.',
        // Stations accredited before the accredited_at column existed can't
        // be placed on a timeline; saying so beats quietly under-reporting.
        footnote: a.stationsAccreditedWithoutDate > 0
            ? '${a.stationsAccreditedWithoutDate} station(s) accredited before this was tracked are not shown.'
            : null,
        child: AdminMonthBarChart(buckets: a.accreditedTrend, color: AppColors.cleared),
      ),
      AdminChartCard(
        title: 'New members',
        subtitle: 'Accounts joining the association, last 6 months',
        isEmpty: memberTotal == 0,
        emptyMessage: 'No new members in the last 6 months.',
        child: AdminMonthBarChart(buckets: a.memberGrowth, color: AdminTheme.chartSeries[3]),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 2 : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
            ],
          );
        }
        const gap = 12.0;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: cardWidth, child: card)],
        );
      },
    );
  }

  /// Turns raw enum values from `accreditation_status` into the words the
  /// rest of the portal already uses on pills and filters.
  Map<String, int> _friendlyMix(Map<String, int> raw) {
    const labels = {
      'accredited': 'Accredited',
      'pending': 'Pending',
      'under_review': 'Under review',
      'rejected': 'Rejected',
      'suspended': 'Suspended',
    };
    final out = <String, int>{};
    for (final entry in raw.entries) {
      final key = labels[entry.key] ?? entry.key;
      out[key] = (out[key] ?? 0) + entry.value;
    }
    return out;
  }
}
