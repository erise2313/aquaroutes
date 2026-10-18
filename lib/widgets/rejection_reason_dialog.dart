import 'package:flutter/material.dart';

/// Asks an officer why a permit or credential is rejected. Returns the
/// trimmed reason, or null if cancelled. Reject stays disabled until a reason
/// is typed: the owner or driver is sent it, and a rejection with no reason
/// leaves them nothing to fix (GTW-WEB-225; the database refuses it too).
Future<String?> promptRejectionReason(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _RejectionReasonDialog());
}

class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    return AlertDialog(
      title: const Text('Rejection reason'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Why is this being rejected?',
            helperText: 'Sent to them, so say what to fix.',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
