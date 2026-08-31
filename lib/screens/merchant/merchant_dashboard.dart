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

        final response = await supabase.from('orders').select('status').eq('station_id', stationId);
        final counts = calculateOrderCounts(response);
        final permits = await _permitService.fetchStationPermits(stationId);
        final renewalDueCount = permits.where((p) => p.isRequired && p.isRenewalDueSoon).length;

        if (mounted) {
          setState(() {
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Text('Station Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildInviteCodeCard(_inviteCode),
                  if (_renewalDueCount > 0) ...[
                    const SizedBox(height: 16),
                    _buildRenewalBanner(),
                  ],
                  const SizedBox(height: 16),

                  Text('Live order overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('Pending', _pendingCount, Colors.red.shade100, Colors.red.shade700)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Active', _activeCount, Colors.orange.shade100, Colors.orange.shade700)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStatCard('Done', _doneCount, Colors.green.shade100, Colors.green.shade700)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Text('Governance & compliance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: onSurface)),
                  const SizedBox(height: 12),
                  _buildNavCard(
                    icon: Icons.folder_shared_outlined,
                    color: Colors.teal,
                    title: 'Permit Vault',
                    subtitle: 'Upload business, sanitary, and (if alkaline) technical permits',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PermitVaultScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.badge_outlined,
                    color: Colors.indigo,
                    title: 'Worker Registry',
                    subtitle: 'Manage worker clearance and file security incidents',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerRegistryScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.fact_check_outlined,
                    color: Colors.teal,
                    title: 'Hire Check',
                    subtitle: 'Search a worker\'s clearance history before hiring them',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HireCheckScreen())),
                  ),
                  const SizedBox(height: 8),
                  _buildNavCard(
                    icon: Icons.swap_horiz,
                    color: Colors.deepPurple,
                    title: 'Jug Clearinghouse',
                    subtitle: 'Settle Slim/Round 5-gal jug balances with other stations',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const JugClearinghouseScreen())),
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
                        MaterialPageRoute(builder: (context) => const DriverManagementScreen()),
                      ).then((_) => _fetchDashboardData());
                    },
                  ),
                ],
              ),
            ),
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
    return Card(
      elevation: 1,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
        title: Text(
          _renewalDueCount == 1 ? '1 permit needs renewal soon' : '$_renewalDueCount permits need renewal soon',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Expiring within 30 days, or already expired.'),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade700),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PermitVaultScreen())).then((_) => _fetchDashboardData()),
      ),
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

  Widget _buildStatCard(String title, int count, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
