import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aquaroute/screens/merchant/driver_management.dart';
import 'package:aquaroute/screens/merchant/hire_check_screen.dart';
import 'package:aquaroute/screens/merchant/jug_clearinghouse_screen.dart';
import 'package:aquaroute/screens/merchant/permit_vault_screen.dart';
import 'package:aquaroute/screens/merchant/worker_registry_screen.dart';
import 'package:aquaroute/services/permit_service.dart';
import 'package:aquaroute/services/supabase_service.dart';
import 'package:aquaroute/utils/formatters.dart';
import '../app_route.dart';
import 'products_screen.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/status_callout.dart';

/// 'assigned' rolls into "active" alongside 'active' (both mean a driver is
/// on it, just not picked up yet vs. en route); 'done' is counted on its
/// own; 'cancelled' is intentionally excluded from every bucket -- the old
/// version miscounted cancelled orders as "done".
Map<String, int> calculateOrderCounts(List<dynamic> orders) {
  int pending = 0, active = 0, done = 0;

  for (final order in orders) {
    final status = order['status']?.toString().toLowerCase();
    if (status == 'pending') {
      pending++;
    } else if (status == 'assigned' || status == 'active') {
      active++;
    } else if (status == 'done') {
      done++;
    }
  }

  return {'pending': pending, 'active': active, 'done': done};
}

/// What a station actually took in, for the owner's own bookkeeping.
class SalesTotals {
  const SalesTotals({this.today = 0, this.week = 0, this.month = 0, this.deliveredToday = 0});

  final double today;
  final double week;
  final double month;
  final int deliveredToday;
}

/// Totals from delivered orders only, in the phone's local time: pending,
/// cancelled and in-flight orders are not money in hand. The week starts on
/// Monday.
SalesTotals calculateSalesTotals(List<dynamic> orders, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final startOfDay = DateTime(current.year, current.month, current.day);
  final startOfWeek = startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
  final startOfMonth = DateTime(current.year, current.month);

  double today = 0, week = 0, month = 0;
  int deliveredToday = 0;

  for (final order in orders) {
    if (order['status']?.toString().toLowerCase() != 'done') continue;
    final createdRaw = order['created_at'];
    if (createdRaw == null) continue;
    final createdAt = DateTime.parse(createdRaw.toString()).toLocal();
    final amount = (order['total_amount'] as num?)?.toDouble() ?? 0;

    if (!createdAt.isBefore(startOfMonth)) month += amount;
    if (!createdAt.isBefore(startOfWeek)) week += amount;
    if (!createdAt.isBefore(startOfDay)) {
      today += amount;
      deliveredToday++;
    }
  }

  return SalesTotals(today: today, week: week, month: month, deliveredToday: deliveredToday);
}

class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  State<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  final supabase = Supabase.instance.client;
  final _permitService = PermitService(SupabaseService.instance);

  int _pendingCount = 0;
  int _activeCount = 0;
  int _doneCount = 0;
  int _renewalDueCount = 0;
  bool _hasNoProducts = false;
  SalesTotals _sales = const SalesTotals();
  String _inviteCode = "Loading...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Get the owner's station id and invite code.
      final stationData = await supabase
          .from('water_stations')
          .select('id, invite_code')
          .eq('owner_profile_id', userId)
          .maybeSingle();

      if (stationData != null) {
        final stationId = stationData['id'] as String;
        final String inviteCode = stationData['invite_code'] ?? 'NO CODE';

        final response = await supabase.from('orders').select('status, total_amount, created_at').eq('station_id', stationId);
        final counts = calculateOrderCounts(response);
        final sales = calculateSalesTotals(response);
        final permits = await _permitService.fetchStationPermits(stationId);
        final renewalDueCount = permits.where((p) => p.isRequired && p.isRenewalDueSoon).length;
        final products = await supabase.from('station_products').select('id').eq('station_id', stationId).eq('is_available', true).limit(1);

        if (mounted) {
          setState(() {
            _hasNoProducts = products.isEmpty;
            _sales = sales;
            _pendingCount = counts['pending']!;
            _activeCount = counts['active']!;
            _doneCount = counts['done']!;
            _renewalDueCount = renewalDueCount;
            _inviteCode = inviteCode;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _inviteCode = "No Station Linked";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching dashboard data: $e');
      if (mounted) {
        setState(() {
          // Was previously left reading the initial "Loading..." placeholder
          // forever on failure, with no indication anything went wrong or
          // that pull-to-refresh (already wired below) would fix it.
          _inviteCode = 'Could not load -- pull to refresh';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Text('Station Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        elevation: 0,
        actions: const [AppThemeToggle(), NotificationBell()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInviteCodeCard(_inviteCode),
                  if (_hasNoProducts) ...[
                    const SizedBox(height: 16),
                    _buildNoProductsBanner(),
                  ],
                  if (_renewalDueCount > 0) ...[
                    const SizedBox(height: 16),
                    _buildRenewalBanner(),
                  ],
                  const SizedBox(height: 16),

                  Text('Live order overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Pending', _pendingCount, Colors.red)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Active', _activeCount, Colors.orange)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Done', _doneCount, Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text('Sales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 12),
                  _buildSalesCard(),
                  const SizedBox(height: 24),

                  Text('Governance & compliance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    icon: Icons.folder_shared_outlined,
                    color: Colors.teal,
                    title: 'Permit Vault',
                    subtitle: 'Upload business, sanitary, and (if alkaline) technical permits',
                    onTap: () => Navigator.push(context, appRoute(const PermitVaultScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.badge_outlined,
                    color: Colors.indigo,
                    title: 'Worker Registry',
                    subtitle: 'Manage worker clearance and file security incidents',
                    onTap: () => Navigator.push(context, appRoute(const WorkerRegistryScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.fact_check_outlined,
                    color: Colors.teal,
                    title: 'Hire Check',
                    subtitle: 'Search a worker\'s clearance history before hiring them',
                    onTap: () => Navigator.push(context, appRoute(const HireCheckScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.swap_horiz,
                    color: Colors.deepPurple,
                    title: 'Jug Clearinghouse',
                    subtitle: 'Settle Slim/Round 5-gal jug balances with other stations',
                    onTap: () => Navigator.push(context, appRoute(const JugClearinghouseScreen())),
                  ),
                  const SizedBox(height: 24),

                  Text('Fleet management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    icon: Icons.local_shipping,
                    color: Colors.blue,
                    title: 'Track & Manage Drivers',
                    subtitle: 'Configure vehicle capacities, plates, and monitor idle drivers',
                    onTap: () {
                      Navigator.push(
                        context,
                        appRoute(const DriverManagementScreen()),
                      ).then((_) => _fetchDashboardData());
                    },
                  ),
                ],
              ),
            ),
    );
  }

  /// Takings from delivered orders. The dashboard could say how many orders
  /// arrived but never what they were worth, which is the number an owner
  /// actually wants at the end of a day.
  Widget _buildSalesCard() {
    final scheme = Theme.of(context).colorScheme;

    Widget figure(String label, double amount, {bool emphasise = false}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              formatPeso(amount),
              style: TextStyle(
                fontSize: emphasise ? 22 : 18,
                fontWeight: FontWeight.bold,
                color: emphasise ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                figure('Today', _sales.today, emphasise: true),
                figure('This week', _sales.week),
                figure('This month', _sales.month),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _sales.deliveredToday == 1
                  ? '1 order delivered today'
                  : '${_sales.deliveredToday} orders delivered today',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// A station with no available product can't take orders at all
  /// (insert_quick_order refuses it), so this says so up front.
  Widget _buildNoProductsBanner() {
    return StatusCallout(
      accent: Colors.orange,
      icon: Icons.sell_outlined,
      title: "Customers can't order from you yet",
      message: 'Add at least one product with a price so your station can take orders.',
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, appRoute(const ProductsScreen())).then((_) => _fetchDashboardData()),
    );
  }

  Widget _buildNavCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade700),
        onTap: onTap,
      ),
    );
  }

  Widget _buildRenewalBanner() {
    return StatusCallout(
      accent: Colors.amber,
      icon: Icons.warning_amber_rounded,
      title: _renewalDueCount == 1 ? '1 permit needs renewal soon' : '$_renewalDueCount permits need renewal soon',
      message: 'Expiring within 30 days, or already expired.',
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.push(context, appRoute(const PermitVaultScreen())).then((_) => _fetchDashboardData()),
    );
  }

  Widget _buildInviteCodeCard(String code) {
    return Card(
      elevation: 2,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "STATION INVITE CODE",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.0, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(code, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue, letterSpacing: 1.5)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.blue, size: 28),
              tooltip: 'Copy Invite Code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Copied invite code '$code' to clipboard!"),
                    backgroundColor: Colors.blue.shade600,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StatusTint.surface(context, accent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatusTint.border(context, accent)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: StatusTint.onTint(context, accent), fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}
