import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/brand_tokens.dart';

enum OrderStepState { done, current, upcoming }

typedef OrderStep = ({String label, DateTime? at, OrderStepState state});

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Placed -> Assigned -> Out for delivery -> Delivered, each with the time
/// the database stamped it (orders.assigned_at etc., patch_help_settings.sql).
/// A cancelled order ends at "Cancelled" (or "Delivery failed") after the
/// last step it reached. Pure, so it is unit-tested.
List<OrderStep> orderSteps(Map<String, dynamic> order) {
  final status = order['status'] as String? ?? 'pending';
  final placed = _time(order['created_at']);
  final assigned = _time(order['assigned_at']);
  final out = _time(order['out_for_delivery_at']);
  final delivered = _time(order['delivered_at']);
  const rank = {'pending': 0, 'assigned': 1, 'active': 2, 'done': 3};

  if (status == 'cancelled') {
    final failed = order['failure_reason'] != null;
    return [
      (label: 'Placed', at: placed, state: OrderStepState.done),
      if (assigned != null) (label: 'Assigned to a driver', at: assigned, state: OrderStepState.done),
      if (out != null) (label: 'Out for delivery', at: out, state: OrderStepState.done),
      (
        label: failed
            ? 'Delivery failed'
            : [
                switch (order['cancelled_by']) {
                  'customer' => 'Cancelled by you',
                  'station' => 'Cancelled by the station',
                  'wasa' => 'Cancelled by WASA',
                  _ => 'Cancelled',
                },
                if ((order['cancel_reason'] as String?)?.isNotEmpty ?? false) '"${order['cancel_reason']}"',
              ].join(' -- '),
        at: _time(order['cancelled_at']) ?? _time(order['failed_at']),
        state: OrderStepState.done,
      ),
    ];
  }

  final reached = rank[status] ?? 0;
  OrderStepState stateOf(int i) => i < reached
      ? OrderStepState.done
      : i == reached
          ? (status == 'done' ? OrderStepState.done : OrderStepState.current)
          : OrderStepState.upcoming;
  return [
    (label: 'Placed', at: placed, state: stateOf(0)),
    (label: 'Assigned to a driver', at: assigned, state: stateOf(1)),
    (label: 'Out for delivery', at: out, state: stateOf(2)),
    (label: 'Delivered', at: delivered, state: stateOf(3)),
  ];
}

/// The steps as a vertical list: a filled check for done, a ring for the
/// current step, a hollow circle for what's next -- shape and words, not
/// colour alone.
class OrderStepTracker extends StatelessWidget {
  const OrderStepTracker({super.key, required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final steps = orderSteps(order);
    final cancelled = order['status'] == 'cancelled';
    final now = DateTime.now();
    String when(DateTime t) => DateFormat(t.year == now.year && t.month == now.month && t.day == now.day ? 'h:mm a' : 'MMM d, h:mm a').format(t);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (steps[i].state) {
                    OrderStepState.done => cancelled && i == steps.length - 1 ? Icons.cancel : Icons.check_circle,
                    OrderStepState.current => Icons.radio_button_checked,
                    OrderStepState.upcoming => Icons.radio_button_unchecked,
                  },
                  size: 22,
                  color: switch (steps[i].state) {
                    OrderStepState.done => cancelled && i == steps.length - 1 ? BrandStatus.danger : BrandStatus.success,
                    OrderStepState.current => theme.colorScheme.primary,
                    OrderStepState.upcoming => muted,
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: steps[i].label,
                        style: TextStyle(
                          fontWeight: steps[i].state == OrderStepState.current ? FontWeight.w700 : FontWeight.w400,
                          color: steps[i].state == OrderStepState.upcoming ? muted : null,
                        ),
                      ),
                      if (steps[i].at != null) TextSpan(text: ' · ${when(steps[i].at!)}', style: TextStyle(color: muted)),
                      if (steps[i].state == OrderStepState.current && steps[i].label != 'Placed')
                        TextSpan(text: ' · now', style: TextStyle(color: muted)),
                    ]),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
