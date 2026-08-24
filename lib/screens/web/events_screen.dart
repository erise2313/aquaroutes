import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../constants/web_theme.dart';
import '../../models/event.dart';
import '../../providers/web_locale_provider.dart';
import '../../services/event_service.dart';
import '../../services/supabase_service.dart';
import '../../web_strings.dart';
import '../../widgets/back_to_top_button.dart';
import '../../widgets/error_state.dart';
import '../../widgets/fade_slide_in.dart';
import '../../widgets/hover_scale.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/web_footer.dart';
import '../../widgets/web_nav_bar.dart';
import '../../widgets/web_page_header.dart';

/// Sorted-by-event_date list of association events -- a list rather than a
/// calendar-grid widget, which keeps scope realistic while still reading as
/// "events calendar" in spirit. Reuses EventService.fetchEvents(), the same
/// query backing events_admin_screen.dart's create/manage view.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  final _eventService = EventService(SupabaseService.instance);
  final _scrollController = ScrollController();

  bool _isLoading = true;
  String? _error;
  List<AssociationEvent> _events = [];

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
      final events = await _eventService.fetchEvents();
      if (mounted) setState(() { _events = events; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load events: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(webLocaleProvider);
    String t(String key) => WebStrings.t(locale, key);

    final upcoming = _events.where((e) => !e.isPast).toList();
    final past = _events.where((e) => e.isPast).toList();

    return Scaffold(
      backgroundColor: WebTheme.paper,
      appBar: const WebNavBar(currentPage: WebPage.events),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                FadeSlideIn(child: WebPageHeader(eyebrow: "WHAT'S COMING UP", title: t('events_title'), subtitle: t('events_intro'))),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_isLoading)
                            const SkeletonList(count: 3, cardHeight: 88)
                          else if (_error != null)
                            ErrorState(message: _error!, onRetry: _load)
                          else ...[
                            if (upcoming.isEmpty && past.isEmpty) const Text('No events scheduled yet.', style: TextStyle(color: Colors.grey)),
                            for (var i = 0; i < upcoming.length; i++)
                              FadeSlideIn(delay: Duration(milliseconds: 140 + i * 50), child: _buildEventCard(upcoming[i])),
                            if (past.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              const Text('Past events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 12),
                              for (final e in past) _buildEventCard(e, isPast: true),
                            ],
                          ],
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

  Widget _buildEventCard(AssociationEvent event, {bool isPast = false}) {
    return HoverScale(
      scale: isPast ? 1.0 : 1.01,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: isPast ? Colors.grey.shade100 : WebTheme.foam, borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: isPast ? Colors.grey.shade300 : WebTheme.harborBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    Text(DateFormat('MMM').format(event.eventDate).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade700 : WebTheme.harborBlue)),
                    Text('${event.eventDate.day}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade700 : WebTheme.harborBlue)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: WebTheme.inkNavy)),
                    const SizedBox(height: 4),
                    Text(DateFormat('MMM d, yyyy · h:mm a').format(event.eventDate), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (event.location != null) Text(event.location!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    if (event.description != null) ...[
                      const SizedBox(height: 8),
                      Text(event.description!, style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
