import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'events_admin_screen.dart';
import 'permit_review_screen.dart';
import 'resources_admin_screen.dart';
import 'worker_clearance_screen.dart';

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
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  int _accreditedCount = 0;
  int _pendingCount = 0;
  int _pendingPermits = 0;
  int _openIncidents = 0;
  int _flaggedWorkers = 0;
  int _expiringSoonPermits = 0;
  List<_ReviewItem> _reviewItems = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final stations = await _supabase.from('water_stations').select('is_accredited');
      final permits = await _supabase
          .from('permits')
          .select('id, permit_type, created_at, expiry_date, water_stations(id, station_name)')
          .eq('status', 'pending_review');
      final expiring = await _supabase
          .from('permits')
          .select('id')
          .eq('status', 'approved')
          .not('expiry_date', 'is', null)
          .lte('expiry_date', DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first);
      final incidents = await _supabase
          .from('worker_incidents')
          .select('id, incident_type, created_at, workers(full_name)')
          .eq('status', 'pending_review');
      final credentials = await _supabase
          .from('worker_credentials')
          .select('id, credential_type, uploaded_at, workers(full_name)')
          .eq('status', 'pending_review');
      final flagged = await _supabase.from('workers').select('id').eq('clearance_status', 'flagged');

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
              MaterialPageRoute(
                builder: (context) => PermitReviewScreen(
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerClearanceScreen()))
                .then((_) => _fetchStats()),
          ),
        for (final c in credentials)
          _ReviewItem(
            label: 'Credential: ${c['credential_type']}',
            subtitle: (c['workers']?['full_name'] as String?) ?? 'Unknown worker',
            createdAt: DateTime.parse(c['uploaded_at'] as String? ?? DateTime.now().toIso8601String()),
            icon: Icons.badge_outlined,
            color: Colors.purple,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerClearanceScreen()))
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
          _reviewItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching admin stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GENTRI WASA Overview')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Station accreditation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statCard('Accredited', _accreditedCount, Colors.green)),
                      const SizedBox(width: 8),
                      Expanded(child: _statCard('Pending', _pendingCount, Colors.amber)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Needs your attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statCard('Permits to Review', _pendingPermits, Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(child: _statCard('Open Incidents', _openIncidents, Colors.deepOrange)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _statCard('Flagged Workers', _flaggedWorkers, Colors.red)),
                      const SizedBox(width: 8),
                      Expanded(child: _statCard('Permits Expiring Soon', _expiringSoonPermits, Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Needs Your Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_reviewItems.isEmpty)
                    const Text('Nothing pending review right now.', style: TextStyle(color: Colors.grey))
                  else
                    ..._reviewItems.map(_buildReviewItemTile),
                  const SizedBox(height: 24),
                  const Text('Content management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0x1A2196F3), child: Icon(Icons.folder_outlined, color: Colors.blue)),
                      title: const Text('Resources Library'),
                      subtitle: const Text('Upload permit checklists, pricing schedules, and other downloads'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ResourcesAdminScreen())),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Color(0x1A3F51B5), child: Icon(Icons.event_outlined, color: Colors.indigo)),
                      title: const Text('Events'),
                      subtitle: const Text('Create and manage upcoming association events'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EventsAdminScreen())),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _statCard(String label, int count, Color color, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$count', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}
