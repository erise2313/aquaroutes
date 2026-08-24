import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: const WebNavBar(currentPage: WebPage.verifyAccreditation),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FadeSlideIn(
                            child: Text(t('verify_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 80),
                            child: Text(t('verify_intro'), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ),
                          const SizedBox(height: 24),
                          FadeSlideIn(
                            delay: const Duration(milliseconds: 140),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() => _hasSearched = true),
                              decoration: const InputDecoration(
                                hintText: 'Enter a station name...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.green.shade50,
      child: ListTile(
        leading: const Icon(Icons.verified, color: Colors.green, size: 32),
        title: Text(station.stationName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${station.barangayName ?? station.stationAddress} · WASA-accredited and verified'),
      ),
    );
  }

  Widget _buildNotFoundCard() {
    return Card(
      color: Colors.red.shade50,
      child: const ListTile(
        leading: Icon(Icons.error_outline, color: Colors.red, size: 32),
        title: Text('No accredited station found by that name', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Double-check the spelling, or the station may not be WASA-accredited.'),
      ),
    );
  }
}
