import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../services/account_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/csv_download.dart';
import '../../utils/csv_export.dart';
import '../../utils/error_text.dart';
import '../../constants/admin_palette.dart';

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
          _error = 'Could not load accounts. ${describeError(e)}';
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  /// The association needs these lists on paper for meetings; the portal
  /// could only ever show them on screen. Exports exactly what's on screen,
  /// filters included, so the file matches what the admin is looking at.
  void _exportCsv() {
    final visible = filterMemberships(_memberships, query: _query, role: _roleFilter, status: _statusFilter);
    final csv = buildCsv(
      const ['Name', 'Role', 'Station', 'Status'],
      visible
          .map((membership) => [
                (membership['profiles']?['full_name'] as String?) ?? 'Unknown',
                membership['role'] == 'station_owner' ? 'Station Owner' : 'Driver / Helper',
                (membership['water_stations']?['station_name'] as String?) ?? '',
                membership['status'] ?? '',
              ])
          .toList(),
    );
    if (!downloadCsv(csvFileName('members'), csv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exporting works in the web admin portal.')),
      );
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
          actions: [
            if (_memberships.isNotEmpty)
              TextButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export'),
              ),
          ],
        ),
        const _DeletionRequestsPanel(),
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
            Icon(icon, size: 56, color: AdminPalette.of(context).ink.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AdminPalette.of(context).ink)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: AdminPalette.of(context).ink.withValues(alpha: 0.6))),
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
              Text('$role${stationName != null ? ' · $stationName' : ''}', style: TextStyle(color: AdminPalette.of(context).inkMuted)),
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

/// Pending account-deletion requests from station owners, drivers and admins
/// (customers delete their own). Hidden when there are none. Deleting runs
/// the delete-account Edge Function, which refuses -- saying why -- while
/// the account still has an open station, deliveries in progress, or is the
/// last admin.
class _DeletionRequestsPanel extends StatefulWidget {
  const _DeletionRequestsPanel();

  @override
  State<_DeletionRequestsPanel> createState() => _DeletionRequestsPanelState();
}

class _DeletionRequestsPanelState extends State<_DeletionRequestsPanel> {
  final _accountService = AccountService(SupabaseService.instance);
  final _supabase = Supabase.instance.client;
  List<AccountDeletionRequest> _requests = [];
  Map<String, Map<String, dynamic>> _membershipByProfile = {};
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = await _accountService.fetchPendingRequests();
      var memberships = <Map<String, dynamic>>[];
      if (requests.isNotEmpty) {
        final rows = await _supabase
            .from('memberships')
            .select('profile_id, role, water_stations(id, station_name, is_active)')
            .inFilter('profile_id', requests.map((r) => r.profileId).toList());
        memberships = List<Map<String, dynamic>>.from(rows);
      }
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _membershipByProfile = {for (final m in memberships) m['profile_id'] as String: m};
      });
    } catch (e) {
      // The rest of the screen still works; the panel just stays hidden.
      debugPrint('Could not load deletion requests: $e');
    }
  }

  void _snack(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String requestId, Future<void> Function() action, String done) async {
    setState(() => _busyId = requestId);
    try {
      await action();
      _snack(done);
      await _load();
    } on AccountException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _closeStation(AccountDeletionRequest request, String stationId, String stationName) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close $stationName?',
      message: 'It stops appearing to customers and can no longer take orders. Its order and jug-ledger history is kept.',
      confirmLabel: 'Close station',
    );
    if (!confirmed) return;
    await _run(
      request.id,
      () => _supabase.from('water_stations').update({'is_active': false, 'accepts_new_orders': false}).eq('id', stationId),
      '$stationName closed.',
    );
  }

  Future<void> _decline(AccountDeletionRequest request) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Decline this request?',
      message: 'The account stays as it is. Let the person know why.',
      confirmLabel: 'Decline',
      isDestructive: false,
    );
    if (!confirmed) return;
    await _run(request.id, () => _accountService.cancelDeletionRequest(request.id), 'Request declined.');
  }

  Future<void> _delete(AccountDeletionRequest request, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      title: "Delete $name's account?",
      message: 'Their login, profile, reviews and comments are removed permanently. Association records '
          '(orders, jug ledger, permits) stay, without their name.',
      confirmLabel: 'Delete account',
    );
    if (!confirmed) return;
    await _run(request.id, () => _accountService.deleteAccountAsAdmin(request.profileId), 'Account deleted.');
  }

  @override
  Widget build(BuildContext context) {
    if (_requests.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.flagged.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.flagged.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Account deletion requests (${_requests.length})',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AdminPalette.of(context).ink),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [for (final request in _requests) _buildRequest(request)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequest(AccountDeletionRequest request) {
    final membership = _membershipByProfile[request.profileId];
    final role = switch (membership?['role']) {
      'station_owner' => 'Station Owner',
      'driver' => 'Driver / Helper',
      'wasa_admin' => 'WASA Admin',
      'public_consumer' => 'Customer',
      _ => 'No role',
    };
    final station = membership?['water_stations'] as Map<String, dynamic>?;
    final stationId = station?['id'] as String?;
    final stationName = station?['station_name'] as String?;
    final stationOpen = station?['is_active'] == true;
    final name = request.fullName ?? 'Unnamed account';
    final busy = _busyId == request.id;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AdminPalette.of(context).ink)),
          Text(
            [
              role,
              if (stationName != null) stationOpen ? stationName : '$stationName (closed)',
              'requested ${DateFormat('MMM d, yyyy').format(request.requestedAt)}',
            ].join(' · '),
            style: TextStyle(color: AdminPalette.of(context).ink.withValues(alpha: 0.65)),
          ),
          if (request.reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('"${request.reason}"', style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (stationOpen && stationId != null && membership?['role'] == 'station_owner')
                OutlinedButton(
                  onPressed: busy ? null : () => _closeStation(request, stationId, stationName ?? 'the station'),
                  child: const Text('Close station'),
                ),
              TextButton(onPressed: busy ? null : () => _decline(request), child: const Text('Decline')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.flagged),
                onPressed: busy ? null : () => _delete(request, name),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Delete account'),
              ),
            ],
          ),
          const Divider(height: 20),
        ],
      ),
    );
  }
}
