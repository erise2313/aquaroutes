import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/event.dart';
import '../../services/event_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/error_state.dart';

class EventsAdminScreen extends StatefulWidget {
  const EventsAdminScreen({super.key});

  @override
  State<EventsAdminScreen> createState() => _EventsAdminScreenState();
}

class _EventsAdminScreenState extends State<EventsAdminScreen> {
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
      if (mounted) setState(() { _events = events; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load events: $e'; _isLoading = false; });
    }
  }

  Future<void> _createFlow() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final locationController = TextEditingController();
    DateTime? eventDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Event'),
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
                    final date = await showDatePicker(context: dialogContext, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
                    if (date == null) return;
                    if (!dialogContext.mounted) return;
                    final time = await showTimePicker(context: dialogContext, initialTime: TimeOfDay.now());
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || eventDate == null || !mounted) return;

    try {
      await _eventService.createEvent(
        title: titleController.text.trim(),
        description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
        eventDate: eventDate!,
        location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event created.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create event: $e')));
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
    return Scaffold(
      appBar: AppBar(title: const Text('Events')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createFlow, icon: const Icon(Icons.add), label: const Text('New Event')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : _events.isEmpty
          ? const Center(child: Text('No events yet.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final e = _events[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.event, color: e.isPast ? Colors.grey : Colors.indigo),
                    title: Text(e.title),
                    subtitle: Text('${DateFormat('MMM d, yyyy h:mm a').format(e.eventDate)}${e.location != null ? ' · ${e.location}' : ''}'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete event', onPressed: () => _delete(e)),
                  ),
                );
              },
            ),
    );
  }
}
