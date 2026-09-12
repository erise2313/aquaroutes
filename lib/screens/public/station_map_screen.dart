import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../services/nearby_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../constants/app_colors.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/app_map_tiles.dart';
import '../../utils/error_text.dart';

/// Public, no-login interactive map/list of every WASA-verified station.
/// Alkaline stations get the animated glowing pulse pin (spec 4D); all pins
/// carry the colorum-verification seal so residents can tell licensed
/// stations apart from unregistered ("colorum") ones at a glance. A station
/// that's temporarily not accepting orders or outside its declared hours
/// still shows (dimmed) instead of vanishing; an admin-deactivated station
/// doesn't appear here at all (filtered server-side by public_stations). A
/// best-effort "near me" sort is applied when location is available.
class StationMapScreen extends StatefulWidget {
  const StationMapScreen({super.key, this.waterTypeFilter});

  final String? waterTypeFilter;

  @override
  State<StationMapScreen> createState() => _StationMapScreenState();
}

class _StationMapScreenState extends State<StationMapScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _nearbyService = NearbyService();
  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  String? _filter;
  bool _showList = false;
  double? _userLat;
  double? _userLng;

  static const _generalTriasCenter = LatLng(14.3868, 120.8817);

  @override
  void initState() {
    super.initState();
    _filter = widget.waterTypeFilter;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      var stations = await _stationService.fetchPublicStations();

      if (mounted) {
        await maybeShowLocationRationale(
          context,
          'GenTri: WASA can use your location to show and sort nearby water stations.',
        );
      }
      final position = await _nearbyService.getCurrentPositionOrNull();
      if (position != null) {
        stations = _nearbyService.sortByDistance(stations, position.latitude, position.longitude);
        _userLat = position.latitude;
        _userLng = position.longitude;
      }

      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the station map. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  List<PublicStation> get _filteredStations {
    if (_filter == null) return _stations;
    return _stations.where((s) => s.offeredWaterTypes.contains(_filter)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStations;
    final mapCenter = _userLat != null && _userLng != null ? LatLng(_userLat!, _userLng!) : _generalTriasCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verified Water Stations'),
        actions: [
          IconButton(
            tooltip: _showList ? 'Show map' : 'Show list',
            icon: Icon(_showList ? Icons.map_outlined : Icons.list),
            onPressed: () => setState(() => _showList = !_showList),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', null),
                        const SizedBox(width: 8),
                        _filterChip('Purified', 'purified'),
                        const SizedBox(width: 8),
                        _filterChip('Mineral', 'mineral'),
                        const SizedBox(width: 8),
                        _filterChip('Alkaline', 'alkaline'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _showList
                      ? _buildList(filtered)
                      : FlutterMap(
                          options: MapOptions(initialCenter: mapCenter, initialZoom: 13),
                          children: [
                            const AppMapTiles(),
                            MarkerLayer(
                              markers: filtered.map((station) {
                                final pin = MapPin(
                                  kind: station.offersAlkaline ? MapPinKind.stationAlkaline : MapPinKind.station,
                                  isAccredited: station.isAccredited,
                                );
                                return Marker(
                                  point: LatLng(station.latitude, station.longitude),
                                  width: 44,
                                  height: 44,
                                  child: GestureDetector(
                                    onTap: () => _showStationSheet(station),
                                    child: station.isOrderable ? pin : Opacity(opacity: 0.45, child: pin),
                                  ),
                                );
                              }).toList(),
                            ),
                            const AppMapAttribution(),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _filterChip(String label, String? value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _buildList(List<PublicStation> stations) {
    final density = PortalDensity.of(context);

    if (stations.isEmpty) {
      return PortalEmptyState(
        icon: Icons.search_off,
        title: 'No stations match',
        message: 'Nothing matches the water type you picked. Try another, or clear the filter.',
        action: _filter == null
            ? null
            : TextButton.icon(
                onPressed: () => setState(() => _filter = null),
                icon: const Icon(Icons.clear),
                label: const Text('Clear filter'),
              ),
      );
    }

    return ListView.builder(
      padding: density.pagePadding,
      itemCount: stations.length,
      itemBuilder: (context, index) =>
          _buildStationCard(stations[index], last: index == stations.length - 1, density: density),
    );
  }

  Widget _buildStationCard(PublicStation station, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final distance = _userLat != null && _userLng != null
        ? _nearbyService.formatDistance(_nearbyService.distanceKm(_userLat!, _userLng!, station))
        : null;

    return PortalCard(
      onTap: () => _showStationSheet(station),
      accent: station.isColorumVerified ? AppColors.seal : null,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.surfaceContainerHighest,
                backgroundImage: station.photoUrl == null ? null : NetworkImage(station.photoUrl!),
                child: station.photoUrl != null ? null : Icon(Icons.storefront, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            station.stationName,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (station.isColorumVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, color: AppColors.cleared, size: 17),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        station.barangayName ?? station.stationAddress,
                        'from ${formatPeso(station.pricePerJug)}',
                        ?distance,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 13),
                  ],
                ),
              ),
            ],
          ),
          // On its own line rather than as a ListTile trailing: a pill beside
          // an expanded name is laid out with unbounded width and can never
          // wrap.
          if (!station.isOrderable) ...[
            const SizedBox(height: 10),
            const StatusPill(label: 'CLOSED', color: AppColors.flagged),
          ],
        ],
      ),
    );
  }

  void _showStationSheet(PublicStation station) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (station.photoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(station.photoUrl!, height: 140, width: double.infinity, fit: BoxFit.cover),
              ),
            if (station.photoUrl != null) const SizedBox(height: 12),
            Text(station.stationName, style: Theme.of(context).textTheme.headlineSmall),
            if (station.isColorumVerified) ...[
              const SizedBox(height: 8),
              const StatusPill(label: 'WASA VERIFIED', color: AppColors.cleared, icon: Icons.verified),
            ],
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final status = stationAvailabilityStatus(acceptsNewOrders: station.acceptsNewOrders, isOpenNow: station.isOpenNow);
              final hoursText = formatStationHours(operatingDays: station.operatingDays, opensAt: station.opensAt, closesAt: station.closesAt);
              if (status.isOpen && hoursText == null) return const SizedBox.shrink();
              // Was a green.shade50 / red.shade50 wash that assumed dark text
              // and stayed pale in dark mode -- the same fault the portals had.
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StatusCallout(
                  accent: status.isOpen ? AppColors.cleared : AppColors.flagged,
                  icon: status.isOpen ? Icons.schedule : Icons.info_outline,
                  title: status.label,
                  message: hoursText,
                  padding: const EdgeInsets.all(12),
                ),
              );
            }),
            Text(
              station.stationAddress + (_userLat != null && _userLng != null ? ' · ${_nearbyService.formatDistance(_nearbyService.distanceKm(_userLat!, _userLng!, station))} away' : ''),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...station.offeredWaterTypes.map((t) => Chip(label: Text(t))),
                ...station.offeredJugTypes.map((j) => Chip(label: Text(j == 'slim_5gal' ? 'Slim 5-gal' : 'Round 5-gal'))),
                if (station.offersJugExchange) const Chip(avatar: Icon(Icons.swap_horiz, size: 16), label: Text('Jug exchange accepted')),
              ],
            ),
            const SizedBox(height: 8),
            Text('From ${formatPeso(station.pricePerJug)} · ${formatPeso(station.deliveryFee)} delivery'),
          ],
        ),
      ),
    );
  }
}
