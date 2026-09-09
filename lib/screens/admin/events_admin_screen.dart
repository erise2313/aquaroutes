import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/admin_theme.dart';
import '../../models/event.dart';
import '../../services/event_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/admin_page_header.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';
import '../../widgets/skeleton_loader.dart';

class EventsAdminScreen extends StatefulWidget {
  const EventsAdminScreen({super.key});

  @override
  State<EventsAdminScreen> createState() => _EventsAdminScreenState();
}

class _EventsAdminScreenState extends State<EventsAdminScreen> {
  final _eventService = EventService(SupabaseService.instance);

  bool _isLoading = true;
  String? _error;
  bool _showPast = false;
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
      if (mounted) setState(() { _events = events; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load events: $e'; _isLoading = false; });
    }
  }

  /// Handles both creating and editing -- passing [editing] pre-fills the
  /// fields and saves via updateEvent instead of createEvent, so there's one
  /// dialog and one set of validation rules rather than two that can drift.
  Future<void> _eventFlow({AssociationEvent? editing}) async {
    final titleController = TextEditingController(text: editing?.title ?? '');
    final descriptionController = TextEditingController(text: editing?.description ?? '');
    final locationController = TextEditingController(text: editing?.location ?? '');
    DateTime? eventDate = editing?.eventDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(editing == null ? 'New Event' : 'Edit Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: descriptionController, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: locationController, decoration: const InputDecoration(labelText: 'Location (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(eventDate == null ? 'Pick date & time' : DateFormat('MMM d, yyyy h:mm a').format(eventDate!)),
                  onPressed: () async {
                    final now = DateTime.now();
                    // An event being edited may already be in the past, and
                    // firstDate must not exclude its own current value or the
                    // picker throws.
                    final initial = eventDate ?? now;
                    final first = initial.isBefore(now) ? initial : now;
                    final date = await showDatePicker(
                      context: dialogContext,
                      initialDate: initial,
                      firstDate: first,
                      lastDate: now.add(const Duration(days: 365 * 3)),
                    );
                    if (date == null) return;
                    if (!dialogContext.mounted) return;
                    final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.fromDateTime(initial));
                    if (time == null) return;
                    setDialogState(() => eventDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: (titleController.text.trim().isEmpty || eventDate == null) ? null : () => Navigator.pop(dialogContext, true),
              child: Text(editing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );

    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final location = locationController.text.trim();
    // Created per dialog, so released per dialog.
    titleController.dispose();
    descriptionController.dispose();
    locationController.dispose();

    if (confirmed != true || eventDate == null || !mounted) return;

    try {
      if (editing == null) {
        await _eventService.createEvent(
          title: title,
          description: description.isEmpty ? null : description,
          eventDate: eventDate!,
          location: location.isEmpty ? null : location,
        );
      } else {
        await _eventService.updateEvent(
          eventId: editing.id,
          title: title,
          description: description.isEmpty ? null : description,
          eventDate: eventDate!,
          location: location.isEmpty ? null : location,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(editing == null ? 'Event created.' : 'Event updated.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save event: $e')));
    }
  }

  Future<void> _delete(AssociationEvent event) async {
    final confirmed = await showConfirmDialog(context, title: 'Delete Event', message: 'Delete "${event.title}"?');
    if (confirmed != true) return;
    try {
      await _eventService.deleteEvent(event.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _events.where((e) => !e.isPast).toList();
    final past = _events.where((e) => e.isPast).toList();
    final visible = _showPast ? past : upcoming;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _eventFlow(),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
      body: Column(
        children: [
          AdminPageHeader(
            title: 'Events',
            subtitle: 'Assemblies and seminars listed on the public website',
            // Past events used to sit in the same list, dimmed. Dimming says
            // "less important", not "already happened" -- and an admin
            // scheduling the next assembly had to scroll through history.
            bottom: SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                backgroundColor: AdminTheme.inkNavy,
                foregroundColor: Colors.white70,
                selectedForegroundColor: AdminTheme.inkNavy,
                selectedBackgroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                minimumSize: const Size(0, 48),
              ),
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.upcoming), label: Text('Upcoming (${upcoming.length})')),
                ButtonSegment(value: true, icon: const Icon(Icons.history), label: Text('Past (${past.length})')),
              ],
              selected: {_showPast},
              onSelectionChanged: (s) => setState(() => _showPast = s.first),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(16), child: SkeletonList(count: 4))
                : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : visible.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final e = visible[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.event, color: e.isPast ? Colors.grey : AdminTheme.harborBlue),
                          title: Text(e.title),
                          subtitle: Text('${DateFormat('MMM d, yyyy h:mm a').format(e.eventDate)}${e.location != null ? ' · ${e.location}' : ''}'),
                          onTap: () => _eventFlow(editing: e),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit event',
                                onPressed: () => _eventFlow(editing: e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Delete event',
                                onPressed: () => _delete(e),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 56, color: AdminTheme.inkNavy.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(
              _showPast ? 'No past events' : 'No upcoming events',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AdminTheme.inkNavy),
            ),
            const SizedBox(height: 8),
            Text(
              _showPast
                  ? 'Events move here automatically once their date has passed.'
                  : 'Create one and it appears on the public website\'s Events page.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AdminTheme.inkNavy.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
