import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/bulletin.dart';
import '../../models/station.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/bulletin_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../auth/login_screen.dart';
import '../auth/registration_screen.dart';
import 'news_screen.dart';
import 'stations_directory_screen.dart';

/// Public front door for the GENTRI WASA website. A hub, not a container --
/// hero + a real stats strip (both numbers are live Supabase queries, never
/// hardcoded) + short teasers into the dedicated Stations and News pages,
/// rather than duplicating their full content inline.
class OrgHomeScreen extends ConsumerStatefulWidget {
  const OrgHomeScreen({super.key});

  @override
  ConsumerState<OrgHomeScreen> createState() => _OrgHomeScreenState();
}

class _OrgHomeScreenState extends ConsumerState<OrgHomeScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _bulletinService = BulletinService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  List<Bulletin> _bulletins = [];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
      final bulletins = await _bulletinService.fetchBulletins();
      if (mounted) {
        setState(() {
          _stations = stations;
          _bulletins = bulletins.take(3).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the homepage: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    final accreditedCount = _stations.where((s) => s.isAccredited).length;
    final barangaysServed = _stations.map((s) => s.barangayName).whereType<String>().toSet().length;

    return Scaffold(
      appBar: const WebNavBar(currentPage: WebPage.home),
      body: Stack(
        children: [
          _isLoading
              ? SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBlock(height: 180, borderRadius: 16),
                            SizedBox(height: 32),
                            SkeletonList(count: 3, cardHeight: 88),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FadeSlideIn(child: _buildHero(t)),
                              const SizedBox(height: 32),
                              FadeSlideIn(delay: const Duration(milliseconds: 100), child: _buildStatsStrip(t, accreditedCount, barangaysServed)),
                              const SizedBox(height: 48),
                              FadeSlideIn(delay: const Duration(milliseconds: 180), child: _buildStationsTeaser(t)),
                              const SizedBox(height: 48),
                              FadeSlideIn(delay: const Duration(milliseconds: 260), child: _buildNewsTeaser(t)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const WebFooter(),
                  ],
                ),
              ),
            ),
          BackToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  Widget _buildHero(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('hero_title'), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t('hero_subtitle'), style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              HoverScale(
                child: ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const RegistrationScreen())),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
                  child: Text(t('hero_register_cta')),
                ),
              ),
              HoverScale(
                child: OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
                  child: Text(t('hero_admin_login_cta')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(String Function(String) t, int accreditedCount, int barangaysServed) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _statCard('$accreditedCount', t('stats_accredited_stations')),
        _statCard('$barangaysServed', t('stats_barangays_served')),
      ],
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildStationsTeaser(String Function(String) t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(t('home_stations_section_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StationsDirectoryScreen())),
              child: Text(t('home_view_all')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_stations.isEmpty)
          const Text('No verified stations yet.', style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _stations.take(3).map(_stationTeaserCard).toList(),
          ),
      ],
    );
  }

  Widget _stationTeaserCard(PublicStation station) {
    return _HoverCard(
      width: 320,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(station.stationName, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (station.isColorumVerified) const Icon(Icons.verified, color: Colors.green, size: 18),
              ],
            ),
            const SizedBox(height: 6),
            Text(station.stationAddress, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 13),
            const SizedBox(height: 8),
            Text('${formatPeso(station.pricePerJug)} / jug', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsTeaser(String Function(String) t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(t('home_news_section_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NewsScreen())),
              child: Text(t('home_view_all')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_bulletins.isEmpty)
          const Text('No announcements yet.', style: TextStyle(color: Colors.grey))
        else
          ..._bulletins.map(
            (b) => HoverScale(
              scale: 1.01,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(b.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(DateFormat('MMM d, yyyy').format(b.createdAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, required this.width});

  final Widget child;
  final double width;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedScale(
        scale: _hovering ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: SizedBox(
          width: widget.width,
          child: Card(elevation: _hovering ? 4 : 1, child: widget.child),
        ),
      ),
    );
  }
}
