import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Clipboard copy action
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aquaroute/screens/merchant/sandbox_screen.dart'; 
import 'package:aquaroute/screens/merchant/driver_management.dart'; // Import Fleet Management screen

class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  State<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  final supabase = Supabase.instance.client;
  
  int _pendingCount = 0;
  int _activeCount = 0;
  int _doneCount = 0;
  String _inviteCode = "Loading...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // Combined fetch function to retrieve both order stats and station invite code in one go
  Future<void> _fetchDashboardData() async {
    try {
      final userId = supabase.auth.currentUser!.id;

      // 1. Get Merchant's Station ID and invite code
      final stationData = await supabase
          .from('water_stations') // Confirmed matching table name
          .select('id, invite_code')
          .eq('owner_id', userId)
          .maybeSingle();

      if (stationData != null) {
        final stationId = stationData['id'];
        final String inviteCode = stationData['invite_code'] ?? 'NO CODE';

        // 2. Fetch order statuses
        final response = await supabase
            .from('orders')
            .select('status')
            .eq('station_id', stationId);

        int pending = 0, active = 0, done = 0;

        for (var order in response) {
          final status = order['status']?.toString().toLowerCase();
          if (status == 'pending') {
            pending++;
          } else if (status == 'active') {
            active++;
          } else {
            done++;
          }
        }

        if (mounted) {
          setState(() {
            _pendingCount = pending;
            _activeCount = active;
            _doneCount = done;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Dashboard', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.redAccent, size: 30),
            tooltip: 'Open Dev Sandbox',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SandboxScreen()),
              ).then((_) => _fetchDashboardData()); // Refresh stats when returning
            },
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- 1. STATION INVITE CODE CARD ---
                  _buildInviteCodeCard(_inviteCode),
                  const SizedBox(height: 16),

                  // --- 2. LIVE ORDER STATISTICS ---
                  const Text('Live order overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
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

                  // --- 3. FLEET QUICK ACTION NAVIGATION ---
                  const Text('Fleet management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: const Icon(Icons.local_shipping, color: Colors.blue),
                      ),
                      title: const Text('Track & Manage Drivers', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Configure vehicle capacities, plates, and monitor idle drivers'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const DriverManagementScreen()),
                        ).then((_) => _fetchDashboardData());
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // Beautiful Invite Code widget containing Copy to Clipboard functionality
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
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.0, fontSize: 12)
                ),
                const SizedBox(height: 4),
                Text(
                  code, 
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blue, letterSpacing: 1.5)
                ),
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
                  )
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
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
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