import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../services/nearby_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/permission_rationale_dialog.dart';
import '../../widgets/star_rating.dart';

/// Public, no-login interactive map/list of every WASA-verified station.
/// Alkaline stations get the animated glowing pulse pin (spec 4D); all pins
/// carry the colorum-verification seal so residents can tell licensed
/// stations apart from unregistered ("colorum") ones at a glance. Closed
/// stations still show (dimmed) instead of vanishing, and a best-effort
/// "near me" sort is applied when location is available.
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
          _error = 'Could not load the station map: $e';
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
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ph.gentriwasa.aquaroute',
                            ),
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
    if (stations.isEmpty) {
      return Center(child: Text('No stations match your filter.', style: TextStyle(color: Colors.grey.shade700)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => _showStationSheet(station),
            leading: CircleAvatar(
              backgroundColor: Colors.grey.shade200,
              backgroundImage: station.photoUrl != null ? NetworkImage(station.photoUrl!) : null,
              child: station.photoUrl == null ? Icon(Icons.storefront, color: Colors.grey.shade700) : null,
            ),
            title: Row(
              children: [
                Expanded(child: Text(station.stationName, overflow: TextOverflow.ellipsis)),
                if (station.isColorumVerified) const Icon(Icons.verified, color: Colors.green, size: 16),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${station.barangayName ?? station.stationAddress} · ${formatPeso(station.pricePerJug)}/jug'
                  '${_userLat != null && _userLng != null ? ' · ${_nearbyService.formatDistance(_nearbyService.distanceKm(_userLat!, _userLng!, station))}' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 2),
                StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 13),
              ],
            ),
            trailing: station.isOrderable
                ? null
                : const Text('Closed', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)),
            isThreeLine: true,
          ),
        );
      },
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
            Row(
              children: [
                Expanded(child: Text(station.stationName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                if (station.isColorumVerified)
                  const Chip(
                    avatar: Icon(Icons.verified, color: Colors.white, size: 16),
                    label: Text('WASA Verified', style: TextStyle(color: Colors.white)),
                    backgroundColor: Colors.green,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!station.isOrderable) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.redAccent, size: 16),
                    SizedBox(width: 6),
                    Text('Currently closed -- not accepting orders', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              station.stationAddress + (_userLat != null && _userLng != null ? ' · ${_nearbyService.formatDistance(_nearbyService.distanceKm(_userLat!, _userLng!, station))} away' : ''),
              style: TextStyle(color: Colors.grey.shade700),
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
            Text('${formatPeso(station.pricePerJug)} / jug · ${formatPeso(station.deliveryFee)} delivery'),
          ],
        ),
      ),
    );
  }
}
