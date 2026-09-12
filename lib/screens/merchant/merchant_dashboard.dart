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
import '../../constants/app_colors.dart';
import '../../widgets/app_theme_toggle.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/portal/portal.dart';

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
    final density = PortalDensity.of(context);

    return Scaffold(
      // The app bar is gone in favour of the portal header, which carries an
      // eyebrow and a subtitle the bar had nowhere to put. The toggle and the
      // bell move into it unchanged.
      body: Column(
        children: [
          const PortalPageHeader(
            eyebrow: 'Your station',
            title: 'Station Dashboard',
            subtitle: 'Live orders, takings, and the records the association asks for',
            showBack: false,
            actions: [AppThemeToggle(), NotificationBell()],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchDashboardData,
                    child: ListView(
                      padding: density.pagePadding,
                      children: [
                        _buildInviteCodeCard(_inviteCode),
                        if (_hasNoProducts) ...[
                          SizedBox(height: density.gap),
                          _buildNoProductsBanner(),
                        ],
                        if (_renewalDueCount > 0) ...[
                          SizedBox(height: density.gap),
                          _buildRenewalBanner(),
                        ],
                        SizedBox(height: density.sectionGap),

                        PortalSection(
                          title: 'Live orders',
                          subtitle: 'Cancelled orders are counted in none of these',
                          child: _buildStatRow(density),
                        ),
                        SizedBox(height: density.sectionGap),

                        PortalSection(
                          title: 'Sales',
                          subtitle: 'Delivered orders only, in your phone\'s time zone',
                          child: _buildSalesCard(),
                        ),
                        SizedBox(height: density.sectionGap),

                        PortalSection(
                          title: 'Governance & compliance',
                          subtitle: 'What the association checks when it reviews your station',
                          child: Column(
                            children: [
                              _buildNavCard(
                                icon: Icons.folder_shared_outlined,
                                tone: AppColors.primary,
                                title: 'Permit Vault',
                                subtitle: 'Upload business, sanitary, and (if alkaline) technical permits',
                                onTap: () => Navigator.push(context, appRoute(const PermitVaultScreen())),
                              ),
                              _buildNavCard(
                                icon: Icons.badge_outlined,
                                tone: AppColors.accent,
                                title: 'Worker Registry',
                                subtitle: 'Manage worker clearance and file security incidents',
                                onTap: () => Navigator.push(context, appRoute(const WorkerRegistryScreen())),
                              ),
                              _buildNavCard(
                                icon: Icons.fact_check_outlined,
                                tone: AppColors.primary,
                                title: 'Hire Check',
                                subtitle: 'Search a worker\'s clearance history before hiring them',
                                onTap: () => Navigator.push(context, appRoute(const HireCheckScreen())),
                              ),
                              _buildNavCard(
                                icon: Icons.swap_horiz,
                                tone: AppColors.accent,
                                title: 'Jug Clearinghouse',
                                subtitle: 'Settle Slim/Round 5-gal jug balances with other stations',
                                onTap: () => Navigator.push(context, appRoute(const JugClearinghouseScreen())),
                                last: true,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: density.sectionGap),

                        PortalSection(
                          title: 'Fleet management',
                          child: _buildNavCard(
                            icon: Icons.local_shipping_outlined,
                            tone: AppColors.primary,
                            title: 'Track & Manage Drivers',
                            subtitle: 'Configure vehicle capacities, plates, and monitor idle drivers',
                            onTap: () {
                              Navigator.push(
                                context,
                                appRoute(const DriverManagementScreen()),
                              ).then((_) => _fetchDashboardData());
                            },
                            last: true,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Pending / Active / Done as counting stat tiles.
  ///
  /// The icons are desk-only: on a phone the three tiles share about 100px
  /// each, and at 200% system text an icon beside the number leaves too
  /// little room for the number itself.
  Widget _buildStatRow(PortalDensity density) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PortalStatTile(
            value: _pendingCount,
            label: 'Pending',
            accent: AppColors.flagged,
            icon: density.isWide ? Icons.hourglass_top_outlined : null,
          ),
        ),
        SizedBox(width: density.gap),
        Expanded(
          child: PortalStatTile(
            value: _activeCount,
            label: 'Active',
            accent: AppColors.pendingClearance,
            icon: density.isWide ? Icons.local_shipping_outlined : null,
          ),
        ),
        SizedBox(width: density.gap),
        Expanded(
          child: PortalStatTile(
            value: _doneCount,
            label: 'Done',
            accent: AppColors.cleared,
            icon: density.isWide ? Icons.check_circle_outline : null,
          ),
        ),
      ],
    );
  }

  /// Takings from delivered orders. The dashboard could say how many orders
  /// arrived but never what they were worth, which is the number an owner
  /// actually wants at the end of a day.
  Widget _buildSalesCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget figure(String label, double amount, {bool emphasise = false}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            // A peso figure has no space to wrap at, so at large system text
            // it would otherwise run past its column. Scaling down keeps all
            // three readable side by side.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatPeso(amount),
                style: (emphasise ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)?.copyWith(
                  color: emphasise ? scheme.primary : scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PortalCard(
      lift: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure('Today', _sales.today, emphasise: true),
              figure('This week', _sales.week),
              figure('This month', _sales.month),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _sales.deliveredToday == 1
                ? '1 order delivered today'
                : '${_sales.deliveredToday} orders delivered today',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
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

  /// One row of the governance and fleet lists: a tinted icon, the name, what
  /// it's for, and a leading colour bar -- the teaser-card treatment the
  /// public site uses, rather than a stack of stock ListTiles.
  Widget _buildNavCard({
    required IconData icon,
    required Color tone,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);

    return PortalCard(
      onTap: onTap,
      accent: tone,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: StatusTint.surface(context, tone), shape: BoxShape.circle),
            child: Icon(icon, color: StatusTint.onTint(context, tone), size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The same slot carries a real code and the "Loading..." / "No Station
    // Linked" / failure placeholders. Only an actual code gets the display
    // treatment -- a wide-tracked sentence set in the heading face reads as
    // broken, not styled.
    final isCode = !code.contains(' ');

    return PortalCard(
      lift: false,
      accent: scheme.primary,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STATION INVITE CODE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.secondary,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    code,
                    style: isCode
                        ? theme.textTheme.headlineSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          )
                        : theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your drivers and helpers enter this to join your station.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            color: scheme.primary,
            tooltip: 'Copy invite code',
            onPressed: !isCode
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Copied invite code '$code' to clipboard!"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}
