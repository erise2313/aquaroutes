import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/error_text.dart';

/// What a customer can report to WASA about a station
/// (station_reports.category, patch_public_trust.sql). Never price: the
/// association governs safety and conduct, not what a station charges.
const stationReportCategories = {
  'taste_smell': 'Water tastes or smells wrong',
  'cloudy': 'Water looks cloudy or has particles',
  'dirty_jug': 'Dirty or damaged jug',
  'late_delivery': 'Very late or missed delivery',
  'driver_conduct': 'Driver behaviour',
  'wrong_order': 'Wrong order delivered',
  'other': 'Something else',
};

const stationReportStatuses = {
  'new': 'Received',
  'reviewing': 'WASA is looking into it',
  'resolved': 'Resolved',
  'dismissed': 'Closed, no action',
};

/// Opens the report form. Returns true once WASA has the report. The station
/// is told a report was made but never who made it.
Future<bool> showReportProblemDialog(
  BuildContext context, {
  required String stationId,
  required String stationName,
  String? orderId,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportProblemDialog(stationId: stationId, stationName: stationName, orderId: orderId),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report sent to WASA. You\'ll get a notification when they update it.')),
    );
  }
  return sent == true;
}

class _ReportProblemDialog extends StatefulWidget {
  const _ReportProblemDialog({required this.stationId, required this.stationName, this.orderId});

  final String stationId;
  final String stationName;
  final String? orderId;

  @override
  State<_ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<_ReportProblemDialog> {
  final _details = TextEditingController();
  String? _category;
  Uint8List? _photo;
  String? _photoName;
  bool _sending = false;

  // Shown inside the dialog. These were SnackBars, which appear behind a
  // dialog's dimmed backdrop where nobody sees them.
  bool _showMissing = false;
  String? _message;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    if (file!.bytes!.length > 5 * 1024 * 1024) {
      if (mounted) setState(() => _message = 'That photo is over 5 MB. Choose a smaller one.');
      return;
    }
    setState(() {
      _message = null;
      _photo = file.bytes;
      _photoName = file.name;
    });
  }

  Future<void> _send() async {
    if (_category == null || _details.text.trim().isEmpty) {
      setState(() {
        _showMissing = true;
        _message = null;
      });
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    final client = Supabase.instance.client;
    try {
      String? photoPath;
      if (_photo != null) {
        final ext = (_photoName ?? 'photo.jpg').split('.').last.toLowerCase();
        photoPath = '${client.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await client.storage.from('station-reports').uploadBinary(photoPath, _photo!);
      }
      await client.from('station_reports').insert({
        'station_id': widget.stationId,
        'order_id': widget.orderId,
        'category': _category,
        'details': _details.text.trim(),
        'photo_path': photoPath,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _message = 'Could not send. ${describeError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Report a problem to WASA'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.orderId == null ? 'About ${widget.stationName}' : 'About your order from ${widget.stationName}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'The association reads every report. The station is told a report was made, '
                'but not who made it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'What went wrong',
                  errorText: _showMissing && _category == null ? 'Choose what went wrong' : null,
                ),
                items: [
                  for (final c in stationReportCategories.entries)
                    DropdownMenuItem(value: c.key, child: Text(c.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _sending ? null : (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _details,
                enabled: !_sending,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                onChanged: (_) {
                  if (_showMissing) setState(() {});
                },
                decoration: InputDecoration(
                  labelText: 'Describe what happened, and when',
                  errorText: _showMissing && _details.text.trim().isEmpty ? 'Describe what happened' : null,
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _sending ? null : _pickPhoto,
                icon: Icon(_photo == null ? Icons.add_a_photo_outlined : Icons.check),
                label: Text(_photo == null ? 'Add a photo (optional)' : 'Photo added -- change'),
              ),
              if (_photoName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_photoName!, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send to WASA'),
        ),
      ],
    );
  }
}
