import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../constants/web_theme.dart';
import '../../models/bulletin.dart';
import '../../models/station.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/bulletin_service.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/count_up_text.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/scroll_reveal.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/wave_divider.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_route.dart';
import '../../widgets/web_seal.dart';
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
  bool _statsRevealed = false;

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
      backgroundColor: WebTheme.paper,
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
                            SkeletonBlock(height: 220, borderRadius: 16),
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
                        FadeSlideIn(child: _buildHero(t)),
                        const WaveDivider(topColor: WebTheme.deepTeal, bottomColor: WebTheme.paper),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ScrollReveal(
                                    onVisible: () => setState(() => _statsRevealed = true),
                                    child: _buildStatsStrip(t, accreditedCount, barangaysServed),
                                  ),
                                  const SizedBox(height: 56),
                                  ScrollReveal(child: _buildStationsTeaser(t)),
                                  const SizedBox(height: 56),
                                  ScrollReveal(child: _buildNewsTeaser(t)),
                                  const SizedBox(height: 40),
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [WebTheme.deepTeal, WebTheme.harborBlue]),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const WebSeal(size: 22),
                  const SizedBox(width: 8),
                  Text('WATER STATION ASSOCIATION · GENERAL TRIAS', style: WebTheme.eyebrow.copyWith(fontSize: 11)),
                ],
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Text(t('hero_title'), style: WebTheme.heroDisplay()),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(t('hero_subtitle'), style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6)),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  HoverScale(
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, webPageRoute(const RegistrationScreen())),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WebTheme.sealGold,
                        foregroundColor: WebTheme.inkNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(t('hero_register_cta'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  HoverScale(
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(context, webPageRoute(const LoginScreen())),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(t('hero_admin_login_cta')),
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

  Widget _buildStatsStrip(String Function(String) t, int accreditedCount, int barangaysServed) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _statCard(accreditedCount, t('stats_accredited_stations')),
        _statCard(barangaysServed, t('stats_barangays_served')),
      ],
    );
  }

  Widget _statCard(int value, String label) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: WebTheme.foam, borderRadius: BorderRadius.circular(10), border: Border.all(color: WebTheme.harborBlue.withValues(alpha: 0.08))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CountUpText(value: value, start: _statsRevealed, style: GoogleFonts.fraunces(fontSize: 36, fontWeight: FontWeight.w600, color: WebTheme.inkNavy)),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(bottom: 6), child: WebSeal(size: 18, outlined: true)),
            ],
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: WebTheme.inkNavy, fontSize: 13)),
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
            Expanded(child: Text(t('home_stations_section_title'), style: WebTheme.display(fontSize: 24))),
            TextButton(
              onPressed: () => Navigator.push(context, webPageRoute(const StationsDirectoryScreen())),
              style: TextButton.styleFrom(foregroundColor: WebTheme.harborBlue),
              child: Text(t('home_view_all')),
            ),
          ],
        ),
        const SizedBox(height: 16),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(station.stationName, style: const TextStyle(fontWeight: FontWeight.bold, color: WebTheme.inkNavy), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (station.isColorumVerified) const WebSeal(size: 20),
              ],
            ),
            const SizedBox(height: 6),
            Text(station.stationAddress, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            StarRatingDisplay(rating: station.avgRating, reviewCount: station.reviewCount, size: 13),
            const SizedBox(height: 10),
            Text('${formatPeso(station.pricePerJug)} / jug', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: WebTheme.harborBlue)),
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
            Expanded(child: Text(t('home_news_section_title'), style: WebTheme.display(fontSize: 24))),
            TextButton(
              onPressed: () => Navigator.push(context, webPageRoute(const NewsScreen())),
              style: TextButton.styleFrom(foregroundColor: WebTheme.harborBlue),
              child: Text(t('home_view_all')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_bulletins.isEmpty)
          const Text('No announcements yet.', style: TextStyle(color: Colors.grey))
        else
          ..._bulletins.map(
            (b) => HoverScale(
              scale: 1.01,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: WebTheme.foam, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold, color: WebTheme.inkNavy)),
                          const SizedBox(height: 4),
                          Text(b.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMM d').format(b.createdAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
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
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hovering ? 0.10 : 0.05), blurRadius: _hovering ? 16 : 8, offset: const Offset(0, 4))],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
