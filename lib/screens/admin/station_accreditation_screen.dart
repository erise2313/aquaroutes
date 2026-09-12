import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../constants/app_colors.dart';
import '../../constants/admin_theme.dart';
import '../../widgets/admin_filter_bar.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/admin_status_pill.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import 'admin_route.dart';
import 'permit_review_screen.dart';
import '../../widgets/app_map_tiles.dart';
import '../../utils/error_text.dart';
import '../../utils/csv_download.dart';
import '../../utils/csv_export.dart';
import '../../constants/admin_palette.dart';

/// Narrows loaded station rows by name/address search and accreditation
/// state. Top-level and pure so the matching rules are unit-testable.
///
/// [state] is one of 'accredited', 'pending', 'deactivated', or null for all.
/// Note 'pending' means accredited == false AND still active -- a deactivated
/// station isn't waiting on anyone, so listing it as pending review would put
/// work in the queue that nobody should act on.
List<Map<String, dynamic>> filterStations(
  List<Map<String, dynamic>> rows, {
  String query = '',
  String? state,
}) {
  final q = query.trim().toLowerCase();
  return rows.where((row) {
    final isAccredited = row['is_accredited'] as bool? ?? false;
    final isActive = row['is_active'] as bool? ?? true;
    switch (state) {
      case 'accredited':
        if (!isAccredited || !isActive) return false;
      case 'pending':
        if (isAccredited || !isActive) return false;
      case 'deactivated':
        if (isActive) return false;
    }
    if (q.isEmpty) return true;
    final name = (row['station_name'] as String?)?.toLowerCase() ?? '';
    final address = (row['station_address'] as String?)?.toLowerCase() ?? '';
    return name.contains(q) || address.contains(q);
  }).toList();
}

/// Association-wide list of all stations, for WASA admins to drill into
/// each one's Permit Vault. Unlike station-owner/driver screens, admins are
/// not scoped to a single station_id -- RLS (0009_rls.sql) grants
/// auth_has_role('wasa_admin') full read access across every station.
/// Also where admin deactivates/reactivates a station -- reversible,
/// hides it from the public map/ordering without deleting anything (see
/// water_stations.is_active, 0002_stations.sql).
///
/// Offers a map view alongside the list -- a labeled two-button
/// SegmentedButton in the header, not a lone unlabeled icon, since admin's
/// users skew older and need the option to actually read, not guess at an
/// icon. Pins colored by the same accredited/pending/deactivated language
/// the list already uses, not new colors.
class StationAccreditationScreen extends StatefulWidget {
  const StationAccreditationScreen({super.key});

  @override
  State<StationAccreditationScreen> createState() => _StationAccreditationScreenState();
}

class _StationAccreditationScreenState extends State<StationAccreditationScreen> {
  static const _generalTriasCenter = LatLng(14.3868, 120.8817);

  /// Above this the list and the coverage map sit side by side; below it they
  /// swap behind the List/Map toggle, which is all a phone has room for.
  static const _sideBySideBreakpoint = 1100.0;

  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  bool _showMap = false;
  List<Map<String, dynamic>> _stations = [];

  String _query = '';
  String? _stateFilter;

  @override
  void initState() {
    super.initState();
    _fetchStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('water_stations')
          .select('id, station_name, station_address, is_accredited, is_colorum_verified, is_active, latitude, longitude')
          .order('station_name');
      if (mounted) {
        setState(() {
          _stations = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load stations. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  /// The accreditation list, as the association needs it for a meeting.
  /// Exports what's on screen, filters included.
  void _exportCsv() {
    final visible = filterStations(_stations, query: _query, state: _stateFilter);
    final csv = buildCsv(
      const ['Station', 'Address', 'Accredited', 'Colorum verified', 'Listed publicly'],
      visible
          .map((station) => [
                station['station_name'] ?? '',
                station['station_address'] ?? '',
                station['is_accredited'] == true ? 'Yes' : 'No',
                station['is_colorum_verified'] == true ? 'Yes' : 'No',
                station['is_active'] == true ? 'Yes' : 'No',
              ])
          .toList(),
    );
    if (!downloadCsv(csvFileName('accreditation status'), csv)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exporting works in the web admin portal.')),
      );
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> station) async {
    final isActive = station['is_active'] as bool? ?? true;
    final stationName = station['station_name'] as String? ?? 'this station';

    final confirmed = await showConfirmDialog(
      context,
      title: isActive ? 'Deactivate Station?' : 'Reactivate Station?',
      message: isActive
          ? '$stationName will disappear from the public map and can no longer accept new orders. This is fully reversible and all its history/permits/orders stay intact.'
          : '$stationName will become visible on the public map and able to accept orders again.',
      confirmLabel: isActive ? 'Deactivate' : 'Reactivate',
      isDestructive: isActive,
    );
    if (!confirmed) return;

    try {
      await _supabase.from('water_stations').update({'is_active': !isActive}).eq('id', station['id'] as String);
      _fetchStations();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accreditedCount = _stations.where((s) => s['is_accredited'] == true).length;
    final visible = filterStations(_stations, query: _query, state: _stateFilter);
    final isFiltered = _query.trim().isNotEmpty || _stateFilter != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= _sideBySideBreakpoint;

        return Column(
          children: [
            AdminPageHeader(
              eyebrow: 'Association',
              title: 'Station Accreditation',
              subtitle: _isLoading ? null : '$accreditedCount of ${_stations.length} stations accredited',
              actions: [
                if (_stations.isNotEmpty)
                  TextButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export'),
                  ),
              ],
              // With the map permanently on screen there is nothing to
              // toggle, so the segmented control only appears when the window
              // is too narrow to show both at once.
              bottom: sideBySide
                  ? null
                  : SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        backgroundColor: AdminTheme.inkNavy,
                        foregroundColor: Colors.white70,
                        selectedForegroundColor: AdminTheme.inkNavy,
                        selectedBackgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        minimumSize: const Size(0, 48),
                      ),
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.list), label: Text('List View')),
                        ButtonSegment(value: true, icon: Icon(Icons.map_outlined), label: Text('Map View')),
                      ],
                      selected: {_showMap},
                      onSelectionChanged: (selection) => setState(() => _showMap = selection.first),
                    ),
            ),
            Expanded(child: _buildBody(visible, isFiltered, sideBySide)),
          ],
        );
      },
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visible, bool isFiltered, bool sideBySide) {
    if (_isLoading) {
      return const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 5, cardHeight: 120));
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _fetchStations);
    if (_stations.isEmpty) {
      return _emptyState(
        icon: Icons.storefront_outlined,
        title: 'No stations registered yet',
        message: 'Stations appear here once an owner registers one from the website.',
      );
    }

    final filterBar = AdminFilterBar(
      searchHint: 'Search by station name or address',
      searchController: _searchController,
      onSearchChanged: (v) => setState(() => _query = v),
      resultSummary: isFiltered ? '${visible.length} of ${_stations.length} stations' : null,
      filters: [
        AdminFilterGroup(
          label: 'Show',
          options: const {
            null: 'All',
            'accredited': 'Accredited',
            'pending': 'Pending Review',
            'deactivated': 'Deactivated',
          },
          selected: _stateFilter,
          onChanged: (v) => setState(() => _stateFilter = v),
        ),
      ],
    );

    final list = visible.isEmpty
        ? _emptyState(
            icon: Icons.search_off,
            title: 'No stations match',
            message: 'Nothing matches the current search and filters.',
            action: TextButton.icon(
              onPressed: () => setState(() {
                _searchController.clear();
                _query = '';
                _stateFilter = null;
              }),
              icon: const Icon(Icons.clear),
              label: const Text('Clear filters'),
            ),
          )
        : RefreshIndicator(
            onRefresh: _fetchStations,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: visible.length,
              itemBuilder: (context, index) => _buildStationCard(visible[index]),
            ),
          );

    if (!sideBySide) {
      // The map ignores the filter bar here only because the bar isn't on
      // screen in map mode; the map itself still respects the active filter.
      if (_showMap) return _buildMap(visible);
      return Column(children: [filterBar, Expanded(child: list)]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(children: [filterBar, Expanded(child: list)]),
        ),
        const VerticalDivider(width: 1),
        // Coverage at a glance, permanently visible rather than behind a
        // toggle nobody discovered. Filtering the list filters the pins too,
        // so "show me only pending stations" answers "and where are they?"
        // in the same action.
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _buildMap(visible),
            ),
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

  Widget _buildStationCard(Map<String, dynamic> station) {
    final palette = AdminPalette.of(context);
    final isAccredited = station['is_accredited'] as bool? ?? false;
    final isVerified = station['is_colorum_verified'] as bool? ?? false;
    final isActive = station['is_active'] as bool? ?? true;
    final statusColor = isAccredited ? AppColors.cleared : AppColors.pendingClearance;

    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: PortalCard(
        accent: statusColor,
        margin: const EdgeInsets.only(bottom: 12),
        onTap: () async {
          await Navigator.push(
            context,
            adminRoute(
              PermitReviewScreen(
                stationId: station['id'] as String,
                stationName: station['station_name'] as String? ?? 'Station',
              ),
            ),
          );
          _fetchStations();
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: StatusTint.surface(context, statusColor),
              child: Icon(
                isAccredited ? Icons.verified : Icons.hourglass_top,
                color: StatusTint.onTint(context, statusColor),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station['station_name'] as String? ?? 'Unnamed Station',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: palette.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station['station_address'] as String? ?? '',
                    style: TextStyle(color: palette.inkMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  // DEACTIVATED joins the other pills here rather than sitting
                  // beside the name: in that Row it was a non-flexible child
                  // laid out with unbounded width, so its label could never
                  // wrap. A Wrap bounds it.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AdminStatusPill(label: isAccredited ? 'ACCREDITED' : 'PENDING REVIEW', color: statusColor),
                      AdminStatusPill(
                        label: isVerified ? 'COLORUM VERIFIED' : 'NOT YET VERIFIED',
                        color: isVerified ? AdminTheme.harborBlue : palette.inkMuted,
                      ),
                      if (!isActive) const AdminStatusPill(label: 'DEACTIVATED', color: AppColors.flagged),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isActive,
                  activeTrackColor: AppColors.cleared,
                  onChanged: (_) => _toggleActive(station),
                ),
                Text(
                  isActive ? 'Active' : 'Inactive',
                  style: TextStyle(fontSize: 11, color: palette.inkMuted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> stations) {
    final withLocation = stations.where((s) => s['latitude'] != null && s['longitude'] != null).toList();
    return FlutterMap(
      options: const MapOptions(initialCenter: _generalTriasCenter, initialZoom: 13),
      children: [
        const AppMapTiles(),
        MarkerLayer(
          markers: withLocation.map((station) {
            return Marker(
              point: LatLng((station['latitude'] as num).toDouble(), (station['longitude'] as num).toDouble()),
              width: 46,
              height: 46,
              child: Tooltip(
                // A bare colored pin doesn't say which station it is until
                // tapped -- a name on hover/long-press matters more here
                // than on the driver/customer maps, since admin is
                // specifically sizing this for older users who benefit
                // from an extra confirmation cue before committing to a tap.
                message: station['station_name'] as String? ?? 'Station',
                // Semantics + InkWell rather than a bare GestureDetector:
                // a tappable pin with no button role and no focus state is
                // invisible to keyboard and screen-reader users.
                child: Semantics(
                  button: true,
                  label: 'Review ${station['station_name'] as String? ?? 'station'}',
                  child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      adminRoute(
                        PermitReviewScreen(
                          stationId: station['id'] as String,
                          stationName: station['station_name'] as String? ?? 'Station',
                        ),
                      ),
                    );
                    _fetchStations();
                  },
                  child: _AccreditationPin(
                    isActive: station['is_active'] as bool? ?? true,
                    isAccredited: station['is_accredited'] as bool? ?? false,
                  ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const AppMapAttribution(),
      ],
    );
  }
}

/// Coverage-map marker colored by the exact same accredited/pending/
/// deactivated language the list view above already uses -- not new
/// colors, just carried onto the map.
class _AccreditationPin extends StatelessWidget {
  const _AccreditationPin({required this.isActive, required this.isAccredited});

  final bool isActive;
  final bool isAccredited;

  @override
  Widget build(BuildContext context) {
    final color = !isActive ? Colors.grey : (isAccredited ? AppColors.cleared : AppColors.pendingClearance);
    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
        ),
        child: Icon(isAccredited ? Icons.verified : Icons.hourglass_top, color: Colors.white, size: 22),
      ),
    );
  }
}
