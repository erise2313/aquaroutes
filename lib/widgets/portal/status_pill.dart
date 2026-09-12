import 'package:flutter/material.dart';

import '../status_callout.dart';

/// A small coloured state label -- accredited, pending, flagged, delivered.
///
/// Promoted from the admin-only version so an order's state in the owner
/// portal and a station's state in admin read identically. The tint and the
/// label colour come from [StatusTint], so a deep green or amber stays
/// legible on a dark surface instead of sinking into it.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});

  final String label;

  /// The semantic colour: green cleared, amber pending, red flagged.
  final Color color;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = StatusTint.onTint(context, color);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: StatusTint.surface(context, color),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StatusTint.border(context, color)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}
