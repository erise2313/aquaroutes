import 'package:flutter/material.dart';

/// Reasons offered when a customer calls an order off.
const customerCancelReasons = [
  'Ordered by mistake',
  'Ordered from another station',
  'Delivery is taking too long',
  'Need to change the product or quantity',
];

/// Reasons offered when the station calls an order off.
const stationCancelReasons = [
  'Out of stock',
  "Can't deliver to that address",
  'Customer asked to cancel',
  "Couldn't reach the customer",
  'Duplicate order',
];

/// Asks why an order is being cancelled (cancel_order needs a reason, and
/// the other side is told it). Returns the reason, or null if they keep the
/// order. Cancelling is only possible before the driver sets out, which the
/// dialog says, since after that the button isn't offered at all.
Future<String?> showCancelOrderDialog(
  BuildContext context, {
  required bool byCustomer,
  required String summary,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CancelOrderDialog(byCustomer: byCustomer, summary: summary),
  );
}

class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.byCustomer, required this.summary});

  final bool byCustomer;
  final String summary;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  static const _other = 'Other';
  final _otherController = TextEditingController();
  String? _choice;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? get _reason {
    if (_choice == null) return null;
    if (_choice != _other) return _choice;
    final text = _otherController.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reasons = [...(widget.byCustomer ? customerCancelReasons : stationCancelReasons), _other];
    return AlertDialog(
      title: const Text('Cancel this order?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.summary),
              const SizedBox(height: 6),
              Text(
                widget.byCustomer
                    ? 'The station is told your reason. Once the driver has left with your order it can no longer be cancelled.'
                    : 'The customer is told your reason. Once the driver has left with the order it can no longer be cancelled.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _choice,
                onChanged: (v) => setState(() => _choice = v),
                child: Column(
                  children: [
                    for (final r in reasons)
                      RadioListTile<String>(value: r, title: Text(r), contentPadding: EdgeInsets.zero),
                  ],
                ),
              ),
              if (_choice == _other)
                TextField(
                  controller: _otherController,
                  autofocus: true,
                  maxLength: 300,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep the order')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
          onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
          child: const Text('Cancel order'),
        ),
      ],
    );
  }
}
