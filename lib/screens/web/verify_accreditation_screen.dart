import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/web_theme.dart';
import '../../models/station.dart';
import '../../models/station_standing.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../web_router.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/station_trust_facts.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_seal.dart';
import '../../utils/error_text.dart';
import 'package:aquaroute/constants/brand_tokens.dart';

/// "Confirm this station is really WASA-accredited" lookup over
/// public_stations. A match says what is true of it -- accredited, or
/// listed with the association but not (or no longer) accredited, with its
/// standing in words. No match is stated neutrally: "not listed" is a fact
/// about the directory, not an accusation against a business that may
/// simply not be a member.
class VerifyAccreditationScreen extends ConsumerStatefulWidget {
  const VerifyAccreditationScreen({super.key});

  @override
  ConsumerState<VerifyAccreditationScreen> createState() => _VerifyAccreditationScreenState();
}

class _VerifyAccreditationScreenState extends ConsumerState<VerifyAccreditationScreen> {
  final _stationService = StationService(SupabaseService.instance);
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<PublicStation> _stations = [];
  bool _hasSearched = false;

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
      if (mounted) setState(() { _stations = stations; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load stations. ${describeError(e)}'; _isLoading = false; });
    }
  }

  List<PublicStation> get _matches {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return [];
    // By name or by WASA station ID (GW-STN-...), which is unique.
    return _stations
        .where((s) => s.stationName.toLowerCase().contains(query) || (s.stationCode ?? '').toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    final matches = _matches;

    return Scaffold(
      backgroundColor: WebTheme.of(context).paper,
      appBar: const WebNavBar(currentPage: WebPage.verifyAccreditation),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: 'VERIFICATION', title: t('verify_title'), subtitle: t('verify_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() => _hasSearched = true),
                            decoration: const InputDecoration(
                              hintText: 'Station name or WASA station ID (GW-STN-...)',
                              prefixIcon: Icon(Icons.search, color: WebTheme.harborBlue),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_isLoading)
                            const SkeletonList(count: 1, cardHeight: 72)
                          else if (_error != null)
                            ErrorState(message: _error!, onRetry: _load)
                          else if (_hasSearched && _searchController.text.trim().isNotEmpty)
                            matches.isEmpty ? _buildNotFoundCard() : Column(children: matches.map(_buildMatchCard).toList()),
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

  Widget _buildMatchCard(PublicStation station) {
    final palette = WebTheme.of(context);
    final accent = station.isAccredited ? WebTheme.sealGold : palette.inkMuted;
    final look = StandingLook.of(stationStandingFromString(station.standing));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: station.isAccredited ? const WebSeal(size: 36) : Icon(look.icon, color: palette.inkMuted, size: 32),
        title: Text(station.stationName, style: TextStyle(fontWeight: FontWeight.bold, color: palette.ink)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.isAccredited
                  ? '${station.barangayName ?? station.stationAddress} · WASA-accredited'
                  : '${station.barangayName ?? station.stationAddress} · Listed with WASA, not accredited',
            ),
            const SizedBox(height: 6),
            StationStandingPills(station: station),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(WebRoutes.station(station.id)),
      ),
    );
  }

  Widget _buildNotFoundCard() {
    return Container(
      // Translucent rather than red.shade50, which stayed pale pink in dark
      // mode under light text. Mirrors the found card's gold treatment.
      // Neutral, not red: a business that isn't a member hasn't done
      // anything wrong by that alone.
      decoration: BoxDecoration(
        color: BrandStatus.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WebTheme.of(context).border),
      ),
      child: ListTile(
        leading: Icon(Icons.info_outline, color: WebTheme.of(context).inkMuted, size: 32),
        title: Text('This station is not listed with GenTri WASA', style: TextStyle(fontWeight: FontWeight.bold, color: WebTheme.of(context).ink)),
        subtitle: const Text('Check the spelling. A station that is not listed has no WASA accreditation to show.'),
      ),
    );
  }
}
