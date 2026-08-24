import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/error_state.dart';

/// Public, no-login interactive map of every WASA-verified station. Alkaline
/// stations get the animated glowing pulse pin (spec 4D); all pins carry
/// the colorum-verification seal so residents can tell licensed stations
/// apart from unregistered ("colorum") ones at a glance.
class StationMapScreen extends StatefulWidget {
  const StationMapScreen({super.key, this.waterTypeFilter});

  final String? waterTypeFilter;

  @override
  State<StationMapScreen> createState() => _StationMapScreenState();
}

class _StationMapScreenState extends State<StationMapScreen> {
  final _stationService = StationService(SupabaseService.instance);
  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  String? _filter;

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
      final stations = await _stationService.fetchPublicStations();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verified Water Stations'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: null, child: Text('All Water Types')),
              PopupMenuItem(value: 'purified', child: Text('Purified')),
              PopupMenuItem(value: 'mineral', child: Text('Mineral')),
              PopupMenuItem(value: 'alkaline', child: Text('Alkaline')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : FlutterMap(
              options: const MapOptions(initialCenter: _generalTriasCenter, initialZoom: 13),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'ph.gentriwasa.aquaroute',
                ),
                MarkerLayer(
                  markers: _filteredStations.map((station) {
                    return Marker(
                      point: LatLng(station.latitude, station.longitude),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showStationSheet(station),
                        child: MapPin(
                          kind: station.offersAlkaline ? MapPinKind.stationAlkaline : MapPinKind.station,
                          isAccredited: station.isAccredited,
                        ),
                      ),
                    );
                  }).toList(),
                ),
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
            Text(station.stationAddress, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 6),
            StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: station.offeredWaterTypes.map((t) => Chip(label: Text(t))).toList(),
            ),
            const SizedBox(height: 8),
            Text('${formatPeso(station.pricePerJug)} / jug · ${formatPeso(station.deliveryFee)} delivery'),
          ],
        ),
      ),
    );
  }
}
