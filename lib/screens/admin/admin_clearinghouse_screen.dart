import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_palette.dart';
import '../../constants/app_colors.dart';
import '../../models/order.dart';
import '../../utils/error_text.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';

/// The jug clearinghouse as the association sees it: every outstanding
/// balance between member stations, and every settlement proposed to clear
/// one.
///
/// Stations settle between themselves -- the station holding the jugs
/// proposes, the station they belong to confirms (confirm_jug_settlement
/// allows nobody else). Officers had no view of any of it, so a dispute
/// between two stations could not even be looked at. Here an officer sees
/// the whole network and can reject a proposed settlement that is in
/// dispute (reject_jug_settlement allows a WASA officer); confirming stays
/// with the station that is owed.
class AdminClearinghouseScreen extends StatefulWidget {
  const AdminClearinghouseScreen({super.key});

  @override
  State<AdminClearinghouseScreen> createState() => _AdminClearinghouseScreenState();
}

class _AdminClearinghouseScreenState extends State<AdminClearinghouseScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _balances = [];
  List<Map<String, dynamic>> _settlements = [];
  Map<String, String> _stationNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _supabase.from('jug_balances').select(),
        _supabase.from('jug_settlements').select().order('created_at', ascending: false),
        _supabase.from('water_stations').select('id, station_name'),
      ]);
      if (!mounted) return;
      setState(() {
        _balances = List<Map<String, dynamic>>.from(results[0] as List);
        _settlements = List<Map<String, dynamic>>.from(results[1] as List);
        _stationNames = {
          for (final s in results[2] as List) (s as Map)['id'] as String: (s['station_name'] as String?) ?? 'Unnamed station',
        };
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the clearinghouse. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  String _station(String? id) => _stationNames[id] ?? 'Unknown station';

  /// Writes WASA's decision on a disputed settlement; both stations are
  /// notified (resolve_jug_dispute, patch_stations_members.sql).


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          AdminPageHeader(
            eyebrow: 'Network',
            title: 'Jug Clearinghouse',
            // View only: settlements are between the two stations (the
            // holder proposes, the owner confirms or rejects). WASA watches;
            // the database refuses any officer change.
            subtitle: 'View only. Jugs stations hold for one another, and the settlements they agree between themselves',
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Balances (${_balances.length})'),
                Tab(text: 'Settlements (${_settlements.length})'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 5))
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : TabBarView(children: [_buildBalances(), _buildSettlements()]),
          ),
        ],
      ),
    );
  }

  Widget _buildBalances() {
    if (_balances.isEmpty) {
      return const PortalEmptyState(
        icon: Icons.swap_horiz,
        title: 'No outstanding balances',
        message: 'When a station delivers to a customer who hands over another station\'s jug, the balance appears here.',
      );
    }
    final palette = AdminPalette.of(context);
    final sorted = [..._balances]..sort((a, b) => ((b['net_qty'] as num).abs()).compareTo((a['net_qty'] as num).abs()));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final b in sorted)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.water_drop_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_station(b['holder_station_id'] as String?)} holds ${(b['net_qty'] as num).abs()} '
                          '${jugTypeLabel(b['jug_type'] as String?) ?? 'jugs'}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink),
                        ),
                        Text('belonging to ${_station(b['owner_station_id'] as String?)}', style: TextStyle(color: palette.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettlements() {
    if (_settlements.isEmpty) {
      return const PortalEmptyState(
        icon: Icons.handshake_outlined,
        title: 'No settlements yet',
        message: 'A station holding another station\'s jugs proposes a settlement when it returns them.',
      );
    }
    final palette = AdminPalette.of(context);
    final fmt = DateFormat('MMM d, yyyy');
    // Open disputes first, then waiting proposals; the rest newest first,
    // as loaded.
    bool disputeOpen(Map<String, dynamic> s) => s['disputed_at'] != null && s['dispute_resolution'] == null;
    final sorted = [
      ..._settlements.where(disputeOpen),
      ..._settlements.where((s) => !disputeOpen(s) && s['status'] == 'proposed'),
      ..._settlements.where((s) => !disputeOpen(s) && s['status'] != 'proposed'),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in sorted)
            PortalCard(
              lift: false,
              margin: const EdgeInsets.only(bottom: 10),
              accent: switch (s['status']) {
                'proposed' => AppColors.pendingClearance,
                'confirmed' => AppColors.cleared,
                _ => AppColors.flagged,
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_station(s['holder_station_id'] as String?)} → ${_station(s['owner_station_id'] as String?)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink),
                        ),
                      ),
                      AdminStatusPill(
                        label: (s['status'] as String? ?? '').toUpperCase(),
                        color: switch (s['status']) {
                          'proposed' => AppColors.pendingClearance,
                          'confirmed' => AppColors.cleared,
                          _ => AppColors.flagged,
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s['quantity']} ${jugTypeLabel(s['jug_type'] as String?) ?? 'jugs'} · proposed '
                    '${fmt.format(DateTime.parse(s['created_at'] as String).toLocal())}'
                    '${s['confirmed_at'] != null ? ' · confirmed ${fmt.format(DateTime.parse(s['confirmed_at'] as String).toLocal())}' : ''}',
                    style: TextStyle(color: palette.inkMuted),
                  ),
                  if (s['dispute_reason'] != null) ...[
                    const SizedBox(height: 6),
                    AdminStatusPill(
                      label: disputeOpen(s) ? 'DISPUTED' : 'DISPUTE DECIDED',
                      color: disputeOpen(s) ? AppColors.pendingClearance : AppColors.cleared,
                      icon: Icons.gavel,
                    ),
                    const SizedBox(height: 4),
                    Text('Reason: ${s['dispute_reason']}', style: TextStyle(color: palette.ink)),
                    if (s['dispute_resolution'] != null)
                      Text('Decision: ${s['dispute_resolution']}', style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700)),
                  ],
                  if (s['status'] == 'proposed') ...[
                    const SizedBox(height: 4),
                    Text(
                      'Waiting for ${_station(s['owner_station_id'] as String?)} to confirm.',
                      style: TextStyle(color: palette.inkMuted, fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
