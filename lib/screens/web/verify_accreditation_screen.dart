import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/web_theme.dart';
import '../../models/station.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/station_service.dart';
import '../../services/supabase_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_seal.dart';

/// "Confirm this station is really WASA-accredited" lookup -- reuses the
/// existing public_stations data (is_colorum_verified/is_accredited), no
/// new backend needed. Only accredited, colorum-verified stations appear in
/// public_stations at all, so a search with no result IS the negative case
/// (rather than needing a separate "not accredited" flag to check).
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
      if (mounted) setState(() { _error = 'Could not load stations: $e'; _isLoading = false; });
    }
  }

  List<PublicStation> get _matches {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return [];
    return _stations.where((s) => s.stationName.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);
    final matches = _matches;

    return Scaffold(
      backgroundColor: WebTheme.paper,
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
                              hintText: 'Enter a station name...',
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
                            matches.isEmpty ? _buildNotFoundCard() : Column(children: matches.map(_buildVerifiedCard).toList()),
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

  Widget _buildVerifiedCard(PublicStation station) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: WebTheme.sealGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: WebTheme.sealGold.withValues(alpha: 0.3))),
      child: ListTile(
        leading: const WebSeal(size: 36),
        title: Text(station.stationName, style: const TextStyle(fontWeight: FontWeight.bold, color: WebTheme.inkNavy)),
        subtitle: Text('${station.barangayName ?? station.stationAddress} · WASA-accredited and verified'),
      ),
    );
  }

  Widget _buildNotFoundCard() {
    return Container(
      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
      child: const ListTile(
        leading: Icon(Icons.error_outline, color: Colors.red, size: 32),
        title: Text('No accredited station found by that name', style: TextStyle(fontWeight: FontWeight.bold, color: WebTheme.inkNavy)),
        subtitle: Text('Double-check the spelling, or the station may not be WASA-accredited.'),
      ),
    );
  }
}
