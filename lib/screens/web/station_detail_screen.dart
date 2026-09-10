import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../constants/web_theme.dart';
import '../../models/station.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../web_router.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_seal.dart';
import '../../widgets/app_map_tiles.dart';

/// A public page per station, at `/stations/<id>`.
///
/// The directory listed stations but its cards had no tap target at all, so
/// on the site whose whole purpose is "which stations are accredited" there
/// was no way to open one. This is also the natural landing page for the
/// Verify Accreditation flow, and gives an accredited member a link they can
/// share as proof.
class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({super.key, required this.stationId});

  final String stationId;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  final _stationService = StationService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  PublicStation? _station;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StationDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Routing straight from one station's URL to another reuses this State,
    // so the id has to be re-read rather than assumed constant.
    if (oldWidget.stationId != widget.stationId) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final station = await _stationService.fetchPublicStation(widget.stationId);
      if (mounted) setState(() { _station = station; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this station: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.stations),
      body: _isLoading
          ? const Padding(padding: EdgeInsets.all(32), child: SkeletonList(count: 3, cardHeight: 120))
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _station == null
          ? _notFound()
          : _buildBody(_station!),
    );
  }

  /// A shared link to a station that has since been deactivated is a normal
  /// thing to happen, not an error -- so this explains it and offers the way
  /// onward rather than showing a failure.
  Widget _notFound() {
    final palette = WebTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 64, 24, 64),
            child: Column(
              children: [
                Icon(Icons.storefront_outlined, size: 64, color: palette.inkMuted),
                const SizedBox(height: 16),
                Text('Station not available', style: WebTheme.display(fontSize: 28)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Text(
                    'This station is no longer listed publicly. It may have been deactivated, '
                    'or the link may be out of date.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.inkMuted, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go(WebRoutes.stations),
                  icon: const Icon(Icons.list),
                  label: const Text('Browse all stations'),
                ),
              ],
            ),
          ),
          const WebFooter(),
        ],
      ),
    );
  }

  Widget _buildBody(PublicStation station) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _header(station),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 860;
                    final details = _detailsColumn(station);
                    final aside = _asideColumn(station);
                    if (!wide) {
                      return Column(children: [details, const SizedBox(height: 24), aside]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: details),
                        const SizedBox(width: 32),
                        Expanded(flex: 2, child: aside),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const WebFooter(),
        ],
      ),
    );
  }

  Widget _header(PublicStation station) {
    final palette = WebTheme.of(context);
    final status = stationAvailabilityStatus(
      acceptsNewOrders: station.acceptsNewOrders,
      isOpenNow: station.isOpenNow,
    );

    return Container(
      width: double.infinity,
      color: palette.foam,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go(WebRoutes.stations),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('All stations'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (station.photoUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        station.photoUrl!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        semanticLabel: 'Photo of ${station.stationName}',
                        errorBuilder: (_, _, _) => _photoFallback(),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(station.stationName, style: WebTheme.display(fontSize: 34)),
                        const SizedBox(height: 6),
                        Text(
                          station.barangayName == null
                              ? station.stationAddress
                              : '${station.stationAddress} · ${station.barangayName}',
                          style: TextStyle(fontSize: 15, color: palette.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (station.isAccredited) _accreditedBadge(),
                            _pill(
                              status.label,
                              status.isOpen ? const Color(0xFF2E7D32) : palette.inkMuted,
                            ),
                            if (station.reviewCount > 0)
                              StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoFallback() {
    return Container(
      width: 96,
      height: 96,
      color: WebTheme.of(context).border,
      child: Icon(Icons.storefront, color: WebTheme.of(context).inkMuted),
    );
  }

  /// The whole reason the site exists -- stated in words next to the seal,
  /// not left as a gold circle the visitor has to interpret.
  Widget _accreditedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WebTheme.sealGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebTheme.sealGold, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WebSeal(size: 20),
          const SizedBox(width: 8),
          Text(
            'WASA Accredited',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: WebTheme.of(context).ink),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
    );
  }

  Widget _detailsColumn(PublicStation station) {
    final hours = formatStationHours(
      operatingDays: station.operatingDays,
      opensAt: station.opensAt,
      closesAt: station.closesAt,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('What they offer'),
        const SizedBox(height: 12),
        _factRow(Icons.local_drink_outlined, 'Water types', _titleCaseList(station.offeredWaterTypes)),
        _factRow(Icons.water_drop_outlined, 'Jug sizes', _jugLabel(station.offeredJugTypes)),
        _factRow(
          Icons.swap_horiz,
          'Jug exchange',
          station.offersJugExchange
              ? 'Accepts jug exchange'
              : 'No jug exchange -- bring your own or buy one here',
        ),
        const SizedBox(height: 28),
        _sectionTitle('Prices'),
        const SizedBox(height: 12),
        _factRow(Icons.payments_outlined, 'Per jug', formatPeso(station.pricePerJug)),
        _factRow(
          Icons.delivery_dining_outlined,
          'Delivery fee',
          station.deliveryFee == 0 ? 'Free delivery' : formatPeso(station.deliveryFee),
        ),
        const SizedBox(height: 28),
        _sectionTitle('Opening hours'),
        const SizedBox(height: 12),
        _factRow(Icons.schedule, 'Schedule', hours ?? 'Hours not published'),
        const SizedBox(height: 28),
        // Ordering is deliberately app-only; saying so beats a visitor
        // hunting the page for an order button that was never going to exist.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WebTheme.of(context).foam,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WebTheme.of(context).border),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone_iphone, color: WebTheme.harborBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Ordering and delivery tracking are in the GenTri WASA mobile app. '
                  'This page is for checking a station\'s accreditation and details.',
                  style: TextStyle(height: 1.5, color: WebTheme.of(context).inkMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _asideColumn(PublicStation station) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Where to find them'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 280,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(station.latitude, station.longitude),
                initialZoom: 15,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                const AppMapTiles(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(station.latitude, station.longitude),
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: '${station.stationName} location',
                        child: Container(
                          decoration: BoxDecoration(
                            color: station.isAccredited ? WebTheme.sealGold : WebTheme.harborBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.storefront, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
                const AppMapAttribution(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(station.stationAddress, style: TextStyle(color: WebTheme.of(context).inkMuted, height: 1.5)),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: WebTheme.display(fontSize: 20));

  Widget _factRow(IconData icon, String label, String value) {
    final palette = WebTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: WebTheme.harborBlue),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: palette.ink)),
          ),
          Expanded(child: Text(value, style: TextStyle(color: palette.inkMuted, height: 1.4))),
        ],
      ),
    );
  }

  String _titleCaseList(List<String> values) {
    if (values.isEmpty) return 'Not specified';
    return values.map((v) => v.isEmpty ? v : v[0].toUpperCase() + v.substring(1)).join(', ');
  }

  String _jugLabel(List<String> jugTypes) {
    if (jugTypes.isEmpty) return 'Not specified';
    return jugTypes
        .map((j) => switch (j) {
              'slim_5gal' => 'Slim 5-gallon',
              'round_5gal' => 'Round 5-gallon',
              _ => j,
            })
        .join(', ');
  }
}
