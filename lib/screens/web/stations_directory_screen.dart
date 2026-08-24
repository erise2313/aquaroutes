import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/custom_map_marker.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';

/// Full station directory for the website -- search + water-type + barangay
/// filters alongside a map, reusing the same StationService.fetchPublicStations
/// query and MapPin marker widget already proven in station_map_screen.dart
/// (the mobile app's equivalent screen), rather than duplicating the query.
class StationsDirectoryScreen extends ConsumerStatefulWidget {
  const StationsDirectoryScreen({super.key});

  @override
  ConsumerState<StationsDirectoryScreen> createState() => _StationsDirectoryScreenState();
}

class _StationsDirectoryScreenState extends ConsumerState<StationsDirectoryScreen> {
  final _stationService = StationService(SupabaseService.instance);
  static const _generalTriasCenter = LatLng(14.3868, 120.8817);

  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String? _waterTypeFilter;
  String? _barangayFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
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
          _error = 'Could not load stations: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<PublicStation> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _stations.where((s) {
      if (query.isNotEmpty && !s.stationName.toLowerCase().contains(query)) return false;
      if (_waterTypeFilter != null && !s.offeredWaterTypes.contains(_waterTypeFilter)) return false;
      if (_barangayFilter != null && s.barangayName != _barangayFilter) return false;
      return true;
    }).toList();
  }

  List<String> get _availableBarangays {
    final set = _stations.map((s) => s.barangayName).whereType<String>().toSet().toList();
    set.sort();
    return set;
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    final filtered = _filtered;

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.stations),
      body: Stack(
        children: [
          _isLoading
              ? SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBlock(width: 220, height: 28),
                            SizedBox(height: 24),
                            SkeletonList(count: 4, cardHeight: 72),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FadeSlideIn(
                              child: Text(t('stations_title'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 16),
                            FadeSlideIn(delay: const Duration(milliseconds: 80), child: _buildFilters(t)),
                            const SizedBox(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth > 900;
                                final list = SizedBox(
                                  height: 500,
                                  width: isWide ? 420 : double.infinity,
                                  child: filtered.isEmpty
                                      ? const Center(child: Text('No stations match your filters.', style: TextStyle(color: Colors.grey)))
                                      : ListView.builder(
                                          itemCount: filtered.length,
                                          itemBuilder: (context, index) => _buildStationCard(filtered[index]),
                                        ),
                                );
                                final map = SizedBox(
                                  height: 500,
                                  width: isWide ? constraints.maxWidth - 420 - 16 : double.infinity,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: FlutterMap(
                                      options: const MapOptions(initialCenter: _generalTriasCenter, initialZoom: 13),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                          userAgentPackageName: 'ph.gentriwasa.aquaroute',
                                        ),
                                        MarkerLayer(
                                          markers: filtered
                                              .map((s) => Marker(
                                                    point: LatLng(s.latitude, s.longitude),
                                                    width: 40,
                                                    height: 40,
                                                    child: MapPin(
                                                      kind: s.offersAlkaline ? MapPinKind.stationAlkaline : MapPinKind.station,
                                                      isAccredited: s.isAccredited,
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                return isWide
                                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [list, const SizedBox(width: 16), Expanded(child: map)])
                                    : Column(children: [list, const SizedBox(height: 16), map]);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const WebFooter(),
                ],
              ),
            ),
          BackToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  Widget _buildFilters(String Function(String) t) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: t('stations_search_hint'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            initialValue: _waterTypeFilter,
            decoration: InputDecoration(labelText: t('stations_filter_water_type'), border: const OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: null, child: Text('Any')),
              DropdownMenuItem(value: 'purified', child: Text('Purified')),
              DropdownMenuItem(value: 'mineral', child: Text('Mineral')),
              DropdownMenuItem(value: 'alkaline', child: Text('Alkaline')),
            ],
            onChanged: (v) => setState(() => _waterTypeFilter = v),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            initialValue: _barangayFilter,
            decoration: InputDecoration(labelText: t('stations_filter_barangay'), border: const OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Barangays')),
              ..._availableBarangays.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setState(() => _barangayFilter = v),
          ),
        ),
      ],
    );
  }

  Widget _buildStationCard(PublicStation station) {
    return HoverScale(
      scale: 1.01,
      child: Card(
      margin: const EdgeInsets.only(bottom: 12, right: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          backgroundImage: station.photoUrl != null ? NetworkImage(station.photoUrl!) : null,
          child: station.photoUrl == null ? const Icon(Icons.storefront, color: Colors.grey) : null,
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
              '${station.barangayName ?? station.stationAddress} · ${formatPeso(station.pricePerJug)}/jug',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 14),
          ],
        ),
        isThreeLine: true,
      ),
      ),
    );
  }
}
