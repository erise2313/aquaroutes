import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_palette.dart';
import '../../models/bulletin.dart';
import '../../models/station.dart';
import '../../services/bulletin_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_text.dart';
import '../../utils/formatters.dart';
import '../../widgets/error_state.dart';
import '../../widgets/portal/portal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/wave_divider.dart';
import '../../widgets/web_seal.dart';

/// The app's landing tab.
///
/// The app used to open on the Bulletin Board -- a filter-chip list of
/// announcements -- while the website opened on a hero, live figures and
/// station teasers. Someone moving between the two saw two different
/// products. This is the website's home page in the app's own theme: same
/// sections, same order, same live figures from the same source
/// (`StationService.fetchPublicStations`, which the website home also reads).
///
/// It is a hub, not a container: every section hands off to the tab that
/// already owns that content rather than duplicating it. The actions switch
/// tabs instead of pushing, so the map and the order form never end up
/// mounted twice with a back stack fighting the bottom bar.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.onOrderWater,
    required this.onFindStation,
    required this.onOpenBoard,
  });

  final VoidCallback onOrderWater;
  final VoidCallback onFindStation;
  final VoidCallback onOpenBoard;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _bulletinService = BulletinService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  List<Bulletin> _bulletins = [];

  /// Held off until the strip has actually been laid out, so the numbers
  /// count up when they come into view rather than racing past during the
  /// first frame.
  bool _statsRevealed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stations = await _stationService.fetchPublicStations();
      final bulletins = await _bulletinService.fetchBulletins();
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _bulletins = bulletins.take(3).toList();
        _isLoading = false;
        _statsRevealed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the home page. ${describeError(e)}';
        _isLoading = false;
      });
    }
  }

  int get _accreditedCount => _stations.where((s) => s.isAccredited).length;

  int get _barangaysServed => _stations.map((s) => s.barangayName).whereType<String>().toSet().length;

  /// Verified stations first, then the ones a customer can actually order
  /// from right now -- a teaser that leads with a closed station wastes the
  /// three slots it has.
  List<PublicStation> get _featured {
    final sorted = [..._stations]..sort((a, b) {
        final verified = (b.isColorumVerified ? 1 : 0) - (a.isColorumVerified ? 1 : 0);
        if (verified != 0) return verified;
        return (b.isOrderable ? 1 : 0) - (a.isOrderable ? 1 : 0);
      });
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final density = PortalDensity.of(context);
    final palette = AppPalette.of(context);

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SkeletonBlock(height: 200, borderRadius: 16),
            SizedBox(height: 24),
            SkeletonList(count: 3, cardHeight: 84),
          ],
        ),
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _buildHero(),
          // The hero's gradient runs top-to-bottom rather than diagonally, so
          // its bottom edge is a single colour and the wave meets it with no
          // seam.
          WaveDivider(topColor: AppColors.accent, bottomColor: palette.paper),
          Padding(
            padding: EdgeInsets.fromLTRB(density.pagePadding.left, 8, density.pagePadding.right, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStats(density),
                SizedBox(height: density.sectionGap),
                PortalSection(
                  title: 'Verified stations',
                  subtitle: 'Accredited by the association, near you',
                  action: TextButton(onPressed: widget.onFindStation, child: const Text('View all')),
                  child: _featured.isEmpty
                      ? const PortalEmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No stations listed yet',
                          message: 'Stations appear here once the association has accredited them.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < _featured.length; i++)
                              _buildStationCard(_featured[i], last: i == _featured.length - 1, density: density),
                          ],
                        ),
                ),
                SizedBox(height: density.sectionGap),
                PortalSection(
                  title: 'Association news',
                  subtitle: 'Announcements, price changes and events',
                  action: TextButton(onPressed: widget.onOpenBoard, child: const Text('View all')),
                  child: _bulletins.isEmpty
                      ? const PortalEmptyState(
                          icon: Icons.campaign_outlined,
                          title: 'No announcements yet',
                          message: 'The association posts notices, price changes and events here.',
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < _bulletins.length; i++)
                              _buildBulletinCard(_bulletins[i], last: i == _bulletins.length - 1, density: density),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.accent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const WebSeal(size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'WATER STATION ASSOCIATION · GENERAL TRIAS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // White on the gradient in both modes: the band is deep blue either
          // way, so this is one of the few places a fixed foreground is right.
          Text(
            'Every jug, certified.',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white, height: 1.15),
          ),
          const SizedBox(height: 10),
          Text(
            'Order from a station the association has actually reviewed -- '
            'and see the seal before you order a drop.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 20),
          // Wrap rather than a Row: at large system text two buttons side by
          // side no longer fit a phone's width.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: widget.onOrderWater,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.seal,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Order water', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              OutlinedButton(
                onPressed: widget.onFindStation,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Find a station'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(PortalDensity density) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PortalStatTile(
            value: _accreditedCount,
            label: 'Accredited stations',
            animate: _statsRevealed,
            icon: Icons.verified_outlined,
          ),
        ),
        SizedBox(width: density.gap),
        Expanded(
          child: PortalStatTile(
            value: _barangaysServed,
            label: 'Barangays served',
            accent: AppColors.accent,
            animate: _statsRevealed,
            icon: Icons.place_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStationCard(PublicStation station, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PortalCard(
      onTap: widget.onFindStation,
      accent: station.isColorumVerified ? AppColors.seal : null,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage: station.photoUrl == null ? null : NetworkImage(station.photoUrl!),
            child: station.photoUrl != null
                ? null
                : Icon(Icons.storefront, color: scheme.onSurfaceVariant, size: 22),
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
                      const WebSeal(size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  station.barangayName ?? station.stationAddress,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 13),
                const SizedBox(height: 6),
                Text(
                  'From ${formatPeso(station.pricePerJug)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletinCard(Bulletin bulletin, {required bool last, required PortalDensity density}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PortalCard(
      onTap: widget.onOpenBoard,
      accent: bulletin.isPinned ? AppColors.pendingClearance : null,
      margin: EdgeInsets.only(bottom: last ? 0 : density.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(bulletin.title, style: theme.textTheme.titleMedium)),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM d').format(bulletin.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bulletin.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
