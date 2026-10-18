import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../constants/app_colors.dart';
import '../../../models/event.dart';
import '../../../services/event_service.dart';
import '../../../services/supabase_service.dart';
import '../../../utils/error_text.dart';
import '../../../widgets/error_state.dart';
import '../../../widgets/event_rsvp.dart';
import '../../../widgets/portal/portal.dart';

/// In-app mirror of the website's Events page (web/events_screen.dart):
/// the association's meetings, seminars and drives, as officers post them
/// (Admin portal, Events).
///
/// Events used to be visible only on the website, so customers, drivers and
/// station owners using the app never saw one even though officers could
/// create them from the app.
class EventsInfoScreen extends StatefulWidget {
  const EventsInfoScreen({super.key});

  @override
  State<EventsInfoScreen> createState() => _EventsInfoScreenState();
}

class _EventsInfoScreenState extends State<EventsInfoScreen> {
  final _eventService = EventService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  List<AssociationEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final events = await _eventService.fetchEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load events. ${describeError(e)}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    final density = PortalDensity.of(context);
    // fetchEvents is oldest first: upcoming ones read soonest first, past
    // ones most recent first.
    final upcoming = _events.where((e) => !e.isPast).toList();
    final past = _events.where((e) => e.isPast).toList().reversed.toList();

    if (_events.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 48),
          PortalEmptyState(
            icon: Icons.event_outlined,
            title: 'No events yet',
            message: 'Association meetings, seminars and drives appear here once WASA posts them.',
          ),
        ],
      );
    }

    return ListView(
      padding: density.pagePadding,
      children: [
        PortalSection(
          title: 'Upcoming',
          child: upcoming.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No upcoming events. Check back soon.'),
                )
              : Column(children: [for (final e in upcoming) _EventCard(event: e)]),
        ),
        if (past.isNotEmpty) ...[
          SizedBox(height: density.sectionGap),
          PortalSection(
            title: 'Past',
            child: Column(children: [for (final e in past) _EventCard(event: e, past: true)]),
          ),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.past = false});

  final AssociationEvent event;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = event.eventDate.toLocal();
    final muted = theme.colorScheme.onSurfaceVariant;

    return PortalCard(
      lift: false,
      accent: past ? muted : AppColors.primary,
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(DateFormat('MMM').format(local).toUpperCase(), style: theme.textTheme.labelSmall),
                Text(DateFormat('d').format(local), style: theme.textTheme.headlineSmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  [DateFormat('EEEE, h:mm a').format(local), if (event.location != null && event.location!.isNotEmpty) event.location!].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (event.description != null && event.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(event.description!.trim()),
                ],
                const SizedBox(height: 8),
                EventRsvpControl(eventId: event.id, isPast: event.isPast),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
