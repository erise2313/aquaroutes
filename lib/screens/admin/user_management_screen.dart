import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/admin_theme.dart';
import '../../constants/app_colors.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';

/// Narrows the loaded membership rows by free-text name/station search plus
/// optional role and status. Kept as a top-level pure function (same pattern
/// as calculateOrderCounts in merchant_dashboard.dart) so the matching rules
/// are unit-testable without pumping a widget.
///
/// [query] matches the person's name OR their station name -- an admin
/// looking for "who runs Aqua Pura" searches the station, not the person.
List<Map<String, dynamic>> filterMemberships(
  List<Map<String, dynamic>> rows, {
  String query = '',
  String? role,
  String? status,
}) {
  final q = query.trim().toLowerCase();
  return rows.where((row) {
    if (role != null && row['role'] != role) return false;
    if (status != null && row['status'] != status) return false;
    if (q.isEmpty) return true;
    final name = (row['profiles']?['full_name'] as String?)?.toLowerCase() ?? '';
    final station = (row['water_stations']?['station_name'] as String?)?.toLowerCase() ?? '';
    return name.contains(q) || station.contains(q);
  }).toList();
}

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
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _memberships = [];

  String _query = '';
  String? _roleFilter;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _fetchMemberships();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMemberships() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load accounts: $e';
          _isLoading = false;
        });
      }
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
    final visible = filterMemberships(
      _memberships,
      query: _query,
      role: _roleFilter,
      status: _statusFilter,
    );
    final isFiltered = _query.trim().isNotEmpty || _roleFilter != null || _statusFilter != null;

    return Column(
      children: [
        AdminPageHeader(
          title: 'User Management',
          subtitle: _memberships.isEmpty ? null : '${_memberships.length} accounts',
        ),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 6))
              : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchMemberships)
              : _memberships.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline,
                  title: 'No accounts yet',
                  message: 'Station owner and driver accounts appear here once they register.',
                )
              : Column(
                  children: [
                    AdminFilterBar(
                      searchHint: 'Search by name or station',
                      searchController: _searchController,
                      onSearchChanged: (v) => setState(() => _query = v),
                      resultSummary: isFiltered ? '${visible.length} of ${_memberships.length} accounts' : null,
                      filters: [
                        AdminFilterGroup(
                          label: 'Role',
                          options: const {null: 'Any', 'station_owner': 'Station Owners', 'driver': 'Drivers'},
                          selected: _roleFilter,
                          onChanged: (v) => setState(() => _roleFilter = v),
                        ),
                        AdminFilterGroup(
                          label: 'Status',
                          options: const {null: 'Any', 'active': 'Active', 'suspended': 'Suspended'},
                          selected: _statusFilter,
                          onChanged: (v) => setState(() => _statusFilter = v),
                        ),
                      ],
                    ),
                    Expanded(
                      // A filtered-to-nothing list is a different situation
                      // from having no accounts, and needs a way back rather
                      // than the same "nothing here" message.
                      child: visible.isEmpty
                          ? _emptyState(
                              icon: Icons.search_off,
                              title: 'No accounts match',
                              message: 'Nothing matches the current search and filters.',
                              action: TextButton.icon(
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  _query = '';
                                  _roleFilter = null;
                                  _statusFilter = null;
                                }),
                                icon: const Icon(Icons.clear),
                                label: const Text('Clear filters'),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchMemberships,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: visible.length,
                                itemBuilder: (context, index) => _buildMembershipTile(visible[index]),
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String message, Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AdminTheme.inkNavy.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AdminTheme.inkNavy)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AdminTheme.inkNavy.withValues(alpha: 0.6))),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
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
          radius: 26,
          backgroundColor: (isActive ? AppColors.cleared : AppColors.flagged).withValues(alpha: 0.14),
          child: Icon(Icons.person, color: isActive ? AppColors.cleared : AppColors.flagged, size: 26),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('$role${stationName != null ? ' · $stationName' : ''}', style: TextStyle(color: Colors.grey.shade700)),
              AdminStatusPill(label: isActive ? 'ACTIVE' : 'SUSPENDED', color: isActive ? AppColors.cleared : AppColors.flagged),
            ],
          ),
        ),
        trailing: TextButton(
          onPressed: () => _toggleStatus(membership),
          child: Text(isActive ? 'Suspend' : 'Reactivate'),
        ),
      ),
    );
  }
}
