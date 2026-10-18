import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_text.dart';

/// Head counts for every event, and the events the signed-in user said
/// they'll attend (event_rsvps, patch_stations_members.sql). Loaded once for
/// a whole list rather than once per card; [refresh] after a change.
class EventRsvpStore extends ChangeNotifier {
  EventRsvpStore._();

  static final instance = EventRsvpStore._();

  Map<String, int> going = {};
  Set<String> mine = {};
  DateTime? _loadedAt;
  Future<void>? _inFlight;

  bool get isSignedIn => Supabase.instance.client.auth.currentUser != null;

  /// Loads at most every 30 seconds unless [force]d.
  Future<void> load({bool force = false}) {
    if (!force && _loadedAt != null && DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return Future.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    final client = Supabase.instance.client;
    try {
      final counts = await client.rpc('event_rsvp_counts');
      going = {for (final r in counts as List) (r as Map)['event_id'] as String: (r['going'] as num).toInt()};
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        final rows = await client.from('event_rsvps').select('event_id').eq('profile_id', userId);
        mine = {for (final r in rows) r['event_id'] as String};
      } else {
        mine = {};
      }
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Counts are a courtesy; the event list works without them.
    }
  }

  Future<void> toggle(String eventId) async {
    final client = Supabase.instance.client;
    if (mine.contains(eventId)) {
      await client.from('event_rsvps').delete().eq('event_id', eventId).eq('profile_id', client.auth.currentUser!.id);
    } else {
      await client.from('event_rsvps').insert({'event_id': eventId});
    }
    await load(force: true);
  }
}

/// "12 going" and, for a signed-in user on an upcoming event, an
/// "I'll attend" toggle.
class EventRsvpControl extends StatefulWidget {
  const EventRsvpControl({super.key, required this.eventId, this.isPast = false, this.textColor});

  final String eventId;
  final bool isPast;
  final Color? textColor;

  @override
  State<EventRsvpControl> createState() => _EventRsvpControlState();
}

class _EventRsvpControlState extends State<EventRsvpControl> {
  final _store = EventRsvpStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await _store.toggle(widget.eventId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _store.going[widget.eventId] ?? 0;
    final attending = _store.mine.contains(widget.eventId);
    final countText = Text(
      widget.isPast ? '$count attended' : (count == 1 ? '1 going' : '$count going'),
      style: TextStyle(fontSize: 16, color: widget.textColor ?? Theme.of(context).colorScheme.onSurfaceVariant),
    );
    if (widget.isPast || !_store.isSignedIn) return countText;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        attending
            ? FilledButton.tonalIcon(
                onPressed: _busy ? null : _toggle,
                icon: const Icon(Icons.check),
                label: const Text("I'll attend -- tap to cancel"),
              )
            : OutlinedButton.icon(
                onPressed: _busy ? null : _toggle,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text("I'll attend"),
              ),
        countText,
      ],
    );
  }
}
