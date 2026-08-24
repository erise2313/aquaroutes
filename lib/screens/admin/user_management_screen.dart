import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/confirm_dialog.dart';

/// Admin-only account suspension for station_owner/driver accounts --
/// deliberately not a true account deletion (that needs a service-role key,
/// which can't safely live in the Flutter client -- would require a
/// separate Supabase Edge Function, out of scope here). Suspending here
/// (memberships.status -> 'suspended') already cuts off access end-to-end:
/// auth_has_role()/auth_station_id() (0003_memberships.sql) both filter
/// status = 'active', and AuthGate (auth_gate.dart) routes a suspended
/// account to AccountSuspendedScreen on their next resolve.
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _memberships = [];

  @override
  void initState() {
    super.initState();
    _fetchMemberships();
  }

  Future<void> _fetchMemberships() async {
    setState(() => _isLoading = true);
    final rows = await _supabase
        .from('memberships')
        .select('id, role, status, profiles(full_name), water_stations(station_name)')
        .inFilter('role', ['station_owner', 'driver'])
        .order('role');
    if (mounted) {
      setState(() {
        _memberships = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> membership) async {
    final isActive = membership['status'] == 'active';
    final name = (membership['profiles']?['full_name'] as String?) ?? 'this account';

    final confirmed = await showConfirmDialog(
      context,
      title: isActive ? 'Suspend Account?' : 'Reactivate Account?',
      message: isActive
          ? '$name will immediately lose access to their portal. This is fully reversible and all their data stays intact.'
          : '$name will regain normal access to their portal.',
      confirmLabel: isActive ? 'Suspend' : 'Reactivate',
      isDestructive: isActive,
    );
    if (!confirmed) return;

    try {
      await _supabase.from('memberships').update({'status': isActive ? 'suspended' : 'active'}).eq('id', membership['id'] as String);
      _fetchMemberships();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memberships.isEmpty
          ? const Center(child: Text('No station owner or driver accounts yet.', style: TextStyle(color: Colors.grey)))
          : RefreshIndicator(
              onRefresh: _fetchMemberships,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _memberships.length,
                itemBuilder: (context, index) => _buildMembershipTile(_memberships[index]),
              ),
            ),
    );
  }

  Widget _buildMembershipTile(Map<String, dynamic> membership) {
    final isActive = membership['status'] == 'active';
    final name = (membership['profiles']?['full_name'] as String?) ?? 'Unknown';
    final role = membership['role'] == 'station_owner' ? 'Station Owner' : 'Driver / Helper';
    final stationName = membership['water_stations']?['station_name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green.shade50 : Colors.red.shade50,
          child: Icon(Icons.person, color: isActive ? Colors.green : Colors.red),
        ),
        title: Text(name),
        subtitle: Text('$role${stationName != null ? ' · $stationName' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: (isActive ? Colors.green : Colors.red).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? 'Active' : 'Suspended',
                style: TextStyle(color: isActive ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _toggleStatus(membership),
              child: Text(isActive ? 'Suspend' : 'Reactivate'),
            ),
          ],
        ),
      ),
    );
  }
}
