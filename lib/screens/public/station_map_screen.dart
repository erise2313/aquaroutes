import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../services/favorite_station_service.dart';
import '../../services/nearby_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../constants/app_colors.dart';
import '../../constants/brand_tokens.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/report_problem_dialog.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/station_trust_facts.dart';
import '../app_route.dart';
import 'quick_order_screen.dart';
import '../../widgets/app_map_tiles.dart';
import '../../utils/error_text.dart';
import '../../utils/data_changes.dart';
import '../../utils/log.dart';

/// Public, no-login interactive map/list of every WASA-verified station.
/// Alkaline stations get the animated glowing pulse pin (spec 4D); all pins
/// carry the colorum-verification seal so residents can tell licensed
/// stations apart from unregistered ("colorum") ones at a glance. A station
/// that's temporarily not accepting orders or outside its declared hours
/// still shows (dimmed) instead of vanishing; an admin-deactivated station
/// doesn't appear here at all (filtered server-side by public_stations).
/// "Accredited only" is on by default; the order is accredited first, then
/// nearest when location is available, with ties rotated daily
/// (orderStationsForCustomers).
class StationMapScreen extends StatefulWidget {
  const StationMapScreen({super.key, this.waterTypeFilter});

  final String? waterTypeFilter;

  @override
  State<StationMapScreen> createState() => _StationMapScreenState();
}

class _StationMapScreenState extends State<StationMapScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _favoriteService = FavoriteStationService(SupabaseService.instance);
  final _nearbyService = NearbyService();
  final _mapController = MapController();
  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  Set<String> _favoriteIds = {};
  String? _filter;
  bool _accreditedOnly = true;
  bool _showList = false;
  double? _userLat;
  double? _userLng;

  static const _generalTriasCenter = LatLng(14.3868, 120.8817);

  /// Where the map should open: on the customer when they are in or near
  /// General Trias, otherwise on General Trias itself -- every station is
  /// there, and a tester at home in another town saw an empty map of their
  /// own street (APP-031).
  static LatLng _centreFor(double? lat, double? lng) {
    if (lat == null || lng == null) return _generalTriasCenter;
    final here = LatLng(lat, lng);
    const nearKm = 15.0;
    final km = const Distance().as(LengthUnit.Kilometer, here, _generalTriasCenter);
    return km <= nearKm ? here : _generalTriasCenter;
  }

  /// A review changed a station's rating: show the new one.
  void _onStationsChanged() => _load();

  @override
  void dispose() {
    DataChanges.stations.removeListener(_onStationsChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    DataChanges.stations.addListener(_onStationsChanged);
    _filter = widget.waterTypeFilter;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stations = await _stationService.fetchPublicStations();

      if (mounted) {
        setState(() {
          _stations = stations;
          _isLoading = false;
        });
      }

      // Same reasoning as the location fix below: the favourites round trip
      // must not hold the list back. Until it lands nothing is starred and
      // nothing is pinned, which is exactly the signed-out state, so the list
      // is correct at every moment rather than merely correct at the end.
      unawaited(_loadFavorites());

      // Deliberately outside the loading gate above. Asking for a location
      // means a rationale dialog the user has to dismiss and then a GPS fix,
      // and the map used to sit behind both -- so the tiles had not even
      // begun downloading while you waited, which is why this screen felt
      // slow to open. The map now draws on the default centre immediately
      // and the "near me" sort drops in later, if a position ever arrives.
      unawaited(_locateAndSort());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the station map. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  /// Best-effort load of the signed-in customer's favourites. A guest gets an
  /// empty set without a round trip, and a failure here leaves the directory
  /// working with nothing starred rather than failing the whole screen -- a
  /// favourite is a convenience, not something worth an error state over.
  Future<void> _loadFavorites() async {
    try {
      final ids = await _favoriteService.fetchIds();
      if (mounted) setState(() => _favoriteIds = ids);
    } catch (e, stack) {
      logError('station_map_screen._loadFavorites', e, stack);
    }
  }

  /// Optimistic: the star flips immediately and is put back if the write
  /// fails. Tapping it is a deliberate action whose result should be visible
  /// at once, and the cost of being wrong is one star in the wrong state.
  Future<void> _toggleFavorite(PublicStation station) async {
    final wasFavorite = _favoriteIds.contains(station.id);
    setState(() {
      wasFavorite ? _favoriteIds.remove(station.id) : _favoriteIds.add(station.id);
    });
    try {
      if (wasFavorite) {
        await _favoriteService.remove(station.id);
      } else {
        await _favoriteService.add(station.id);
      }
    } catch (e, stack) {
      logError('station_map_screen._toggleFavorite', e, stack);
      if (!mounted) return;
      setState(() {
        wasFavorite ? _favoriteIds.add(station.id) : _favoriteIds.remove(station.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your favourites. Please try again.')),
      );
    }
  }

  /// Best-effort "near me" sort. Never gates the map: a denial, a timeout or
  /// no fix at all simply leaves the list in the order the server returned.
  Future<void> _locateAndSort() async {
    if (mounted) {
      await maybeShowLocationRationale(
        context,
        'GenTri: WASA can use your location to show and sort nearby water stations.',
      );
    }
    final position = await _nearbyService.getCurrentPositionOrNull();
    if (position == null || !mounted) return;
    setState(() {
      _userLat = position.latitude;
      _userLng = position.longitude;
    });

    // The map is already on screen by the time a fix arrives, and
    // MapOptions.initialCenter only applies to the first build -- so without
    // this it would stay on the General Trias default, where it used to open
    // centred on you. Throws when the map is not currently mounted (the list
    // view is showing instead), which is harmless: mapCenter in build() then
    // centres it correctly the next time the map is built.
    try {
      _mapController.move(_centreFor(position.latitude, position.longitude), 13);
    } catch (_) {}
  }

  /// Filter first, then order, then pin: a favourite that the active
  /// filters exclude stays excluded, rather than being pulled back in by its
  /// star.
  List<PublicStation> get _filteredStations {
    final filtered = _stations
        .where((s) => _filter == null || s.offeredWaterTypes.contains(_filter))
        .where((s) => !_accreditedOnly || s.isAccredited)
        .toList();
    final lat = _userLat, lng = _userLng;
    final ordered = orderStationsForCustomers(
      filtered,
      distanceKm: lat == null || lng == null ? null : (s) => _nearbyService.distanceKm(lat, lng, s),
    );
    return FavoriteStationService.pinFavorites(ordered, _favoriteIds);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredStations;
    final mapCenter = _centreFor(_userLat, _userLng);

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
                        FilterChip(
                          label: const Text('Accredited only'),
                          avatar: const Icon(Icons.verified_outlined, size: 18),
                          selected: _accreditedOnly,
                          onSelected: (v) => setState(() => _accreditedOnly = v),
                        ),
                        const SizedBox(width: 16),
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
                          mapController: _mapController,
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
        message: _accreditedOnly
            ? 'No accredited station matches. Turn off "Accredited only" to see every listed station.'
            : 'Nothing matches the water type you picked. Try another, or clear the filter.',
        action: _accreditedOnly
            ? TextButton.icon(
                onPressed: () => setState(() => _accreditedOnly = false),
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Show all stations'),
              )
            : _filter == null
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
    final isFavorite = _favoriteIds.contains(station.id);

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
              // Hidden entirely for guests rather than shown and then refused:
              // a control that only ever produces a "sign in first" message is
              // worse than no control. Sized to the 48dp minimum touch target.
              if (_favoriteService.isSignedIn)
                IconButton(
                  onPressed: () => _toggleFavorite(station),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: isFavorite ? 'Remove from favourites' : 'Save to favourites',
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? AppColors.seal : scheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
            ],
          ),
          // On its own line rather than as a ListTile trailing: a pill beside
          // an expanded name is laid out with unbounded width and can never
          // wrap.
          if (!station.isOrderable || station.standing == 'lapsed' || station.isNewMember()) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!station.isOrderable) const StatusPill(label: 'CLOSED', color: AppColors.flagged),
                // Lapsed stays orderable (decision of 18 Oct 2026) but says so.
                if (station.standing == 'lapsed') const StatusPill(label: 'LAPSED', color: BrandStatus.danger, icon: Icons.error_outline),
                if (station.isNewMember()) const StatusPill(label: 'NEW MEMBER', color: BrandStatus.info, icon: Icons.fiber_new_outlined),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showStationSheet(PublicStation station) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
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
            const SizedBox(height: 16),
            Text('Association record', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            StationTrustPanel(station: station),
            const SizedBox(height: 8),
            // Signed out, the order form shows its own sign-in prompt.
            FilledButton.icon(
              onPressed: station.isOrderable
                  ? () {
                      Navigator.pop(context);
                      Navigator.push(context, appRoute(QuickOrderScreen(prefill: OrderPrefill(stationId: station.id))));
                    }
                  : null,
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(station.isOrderable ? 'Order from this station' : 'Not taking orders right now'),
            ),
            if (_favoriteService.isSignedIn)
              TextButton.icon(
                onPressed: () => showReportProblemDialog(context, stationId: station.id, stationName: station.stationName),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Report a problem to WASA'),
              ),
          ],
        ),
      ),
    );
  }
}
