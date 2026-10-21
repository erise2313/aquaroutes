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
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../utils/csv_download.dart';
import '../../utils/csv_export.dart';
import '../../utils/error_text.dart';
import '../../constants/admin_palette.dart';
import '../../widgets/officer_can.dart';
import '../../utils/log.dart';

/// Narrows the loaded membership rows by free-text name/station search plus
/// optional role and status. Kept as a top-level pure function (same pattern
/// as calculateOrderCounts in merchant_dashboard.dart) so the matching rules
/// are unit-testable without pumping a widget.
///
/// [query] matches the person's name, their phone number OR their station
/// name -- an admin looking for "who runs Aqua Pura" searches the station,
/// and a customer is often known only by the number they order with.
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
    final phone = (row['profiles']?['phone_number'] as String?)?.toLowerCase() ?? '';
    return name.contains(q) || station.contains(q) || (phone.isNotEmpty && phone.contains(q));
  }).toList();
}

/// How each role is named across the Users screen and its export.
String membershipRoleLabel(String? role) => switch (role) {
      'station_owner' => 'Station Owner',
      'driver' => 'Driver / Helper',
      'public_consumer' => 'Customer',
      'wasa_admin' => 'WASA Officer',
      'wasa_superadmin' => 'WASA Super Admin',
      'station_staff' => 'Station Staff',
      _ => 'No role',
    };

/// Every account in the association -- customers, drivers, station owners
/// and officers -- with suspension for each.
///
/// It used to list only station owners and drivers, so a customer abusing
/// the system (fake orders, abusive posts or reviews) could not be found or
/// stopped from the portal, and officers could not see one another.
///
/// Suspension is deliberately not a true account deletion (that needs a service-role key,
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

  /// Officer rows can only be changed by a super admin (the database
  /// enforces it); everyone else sees who they are but no button.
  bool _viewerIsSuperadmin = false;

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
          .select('id, profile_id, role, status, profiles(full_name, phone_number), water_stations(station_name)')
          .order('role');
      final isSuper = await _supabase.rpc('auth_is_superadmin');
      if (mounted) {
        setState(() {
          _memberships = List<Map<String, dynamic>>.from(rows);
          _viewerIsSuperadmin = isSuper == true;
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
          ? '$name will immediately lose access${membership['role'] == 'public_consumer' ? ', including ordering' : ' to their portal'}. '
              'This is fully reversible and all their data stays intact.'
          : '$name will regain normal access.',
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
      const ['Name', 'Role', 'Phone', 'Station', 'Status'],
      visible
          .map((membership) => [
                (membership['profiles']?['full_name'] as String?) ?? 'Unknown',
                membershipRoleLabel(membership['role'] as String?),
                (membership['profiles']?['phone_number'] as String?) ?? '',
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
          eyebrow: 'Association',
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
        const OfficerCan(area: OfficerArea.accounts, child: _SuspensionAppealsPanel()),
        Expanded(
          child: _isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 6))
              : _error != null
              ? ErrorState(message: _error!, onRetry: _fetchMemberships)
              : _memberships.isEmpty
              ? _emptyState(
                  icon: Icons.people_outline,
                  title: 'No accounts yet',
                  message: 'Accounts appear here once people register.',
                )
              : Column(
                  children: [
                    AdminFilterBar(
                      searchHint: 'Search by name, phone or station',
                      searchController: _searchController,
                      onSearchChanged: (v) => setState(() => _query = v),
                      resultSummary: isFiltered ? '${visible.length} of ${_memberships.length} accounts' : null,
                      filters: [
                        AdminFilterGroup(
                          label: 'Role',
                          options: const {
                            null: 'Any',
                            'public_consumer': 'Customers',
                            'driver': 'Drivers',
                            'station_owner': 'Station Owners',
                            'station_staff': 'Station Staff',
                            'wasa_admin': 'Officers',
                            'wasa_superadmin': 'Super Admins',
                          },
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

  /// One empty state for the whole portal now -- admin had four near-identical
  /// copies of this helper.
  Widget _emptyState({required IconData icon, required String title, required String message, Widget? action}) {
    return PortalEmptyState(icon: icon, title: title, message: message, action: action);
  }

  Widget _buildMembershipTile(Map<String, dynamic> membership) {
    final palette = AdminPalette.of(context);
    final isActive = membership['status'] == 'active';
    final name = (membership['profiles']?['full_name'] as String?) ?? 'Unknown';
    final role = membershipRoleLabel(membership['role'] as String?);
    final stationName = membership['water_stations']?['station_name'] as String?;
    final phone = membership['profiles']?['phone_number'] as String?;
    final tone = isActive ? AppColors.cleared : AppColors.flagged;
    // An officer suspending their own account would lock themselves out of
    // the portal with no one left to undo it.
    final isSelf = membership['profile_id'] == _supabase.auth.currentUser?.id;
    final isOfficerRow = membership['role'] == 'wasa_admin' || membership['role'] == 'wasa_superadmin';

    return PortalCard(
      lift: false,
      accent: tone,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: StatusTint.surface(context, tone),
            child: Icon(Icons.person, color: StatusTint.onTint(context, tone), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [role, ?stationName, if (phone != null && phone.isNotEmpty) phone].join(' · '),
                      style: TextStyle(color: palette.inkMuted),
                    ),
                    AdminStatusPill(label: isActive ? 'ACTIVE' : 'SUSPENDED', color: tone),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isSelf)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text('You', style: TextStyle(color: palette.inkMuted, fontWeight: FontWeight.w600)),
            )
          else if (isOfficerRow && !_viewerIsSuperadmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Tooltip(
                message: 'Officer accounts are managed by the super admins (Officers page).',
                child: Text('Super admins manage', style: TextStyle(color: palette.inkMuted)),
              ),
            )
          else
            OfficerCan(area: OfficerArea.accounts, child: TextButton(
              onPressed: () => _toggleStatus(membership),
              child: Text(isActive ? 'Suspend' : 'Reactivate'),
            )),
        ],
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
      logError('deletion requests', e);
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
            // A share of the screen, not a fixed 320 px: on a phone that,
            // with the header and filters, left no room for the user list.
            constraints: BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height * 0.25).clamp(140.0, 320.0)),
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
    final role = membershipRoleLabel(membership?['role'] as String?);
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
          OfficerCan(area: OfficerArea.accounts, child: Wrap(
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
          )),
          const Divider(height: 20),
        ],
      ),
    );
  }
}

/// Appeals from suspended accounts (submit_account_appeal). A full officer
/// or super admin reinstates the account or keeps it suspended, with a note
/// the person reads on their suspended screen.
class _SuspensionAppealsPanel extends StatefulWidget {
  const _SuspensionAppealsPanel();

  @override
  State<_SuspensionAppealsPanel> createState() => _SuspensionAppealsPanelState();
}

class _SuspensionAppealsPanelState extends State<_SuspensionAppealsPanel> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _appeals = [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supabase
          .from('account_appeals')
          .select('id, profile_id, appeal_text, created_at, profiles!account_appeals_profile_id_fkey(full_name)')
          .eq('status', 'pending')
          .order('created_at');
      if (mounted) setState(() => _appeals = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Nothing to show is the same as nothing pending here.
    }
  }

  Future<void> _decide(Map<String, dynamic> appeal, bool reinstate) async {
    final note = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(reinstate ? 'Reinstate this account?' : 'Keep the account suspended?'),
          content: TextField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Note to the person',
              hintText: reinstate ? 'e.g. Checked your orders; reinstated.' : 'e.g. The incident was confirmed by the station.',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (note.text.trim().length < 3) {
                  setDialogState(() => error = 'Write a short note for the person.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(reinstate ? 'Reinstate' : 'Keep suspended'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = appeal['id'] as String);
    try {
      await _supabase.rpc('decide_account_appeal', params: {
        'p_appeal_id': appeal['id'],
        'p_reinstate': reinstate,
        'p_note': note.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(reinstate ? 'Account reinstated. Refresh the list to see it as Active.' : 'Kept suspended; they have been told.'),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_appeals.isEmpty) return const SizedBox.shrink();
    final palette = AdminPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.pendingClearance.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.pendingClearance.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appeals against suspension (${_appeals.length})',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: palette.ink),
          ),
          for (final a in _appeals) ...[
            const SizedBox(height: 10),
            Text(
              (a['profiles'] as Map?)?['full_name'] as String? ?? 'Unnamed',
              style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
            ),
            Text(
              'Appealed ${DateFormat('MMM d, yyyy').format(DateTime.parse(a['created_at'] as String).toLocal())}',
              style: TextStyle(color: palette.inkMuted),
            ),
            const SizedBox(height: 4),
            Text('"${a['appeal_text']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busyId != null ? null : () => _decide(a, false),
                  child: const Text('Keep suspended'),
                ),
                FilledButton(
                  onPressed: _busyId != null ? null : () => _decide(a, true),
                  child: const Text('Reinstate'),
                ),
              ],
            ),
            const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}
