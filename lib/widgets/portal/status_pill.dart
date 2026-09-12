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
    final style = TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: StatusTint.surface(context, color),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StatusTint.border(context, color)),
      ),
      // Deliberately one Text rather than a Row of icon + label. A Row lays
      // its non-flexible children out with unbounded width whatever the
      // constraints coming in, so the label could never wrap: a long status
      // at large system text ("OUT FOR DELIVERY" at 200%) simply ran off the
      // card it sat on. Flexible isn't the answer either -- it asserts
      // wherever a pill sits inside another Row, which is most call sites.
      // A single Text wraps when it is given a bound and sizes naturally
      // when it isn't.
      //
      // Plain Text unless there's an icon to inline, so the common pill stays
      // an ordinary Text: rich text is invisible to find.text() in widget
      // tests unless they ask for it, and most pills are only ever labels.
      child: icon == null
          ? Text(label, style: style)
          : Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(icon, size: 13, color: foreground),
                    ),
                  ),
                  TextSpan(text: label),
                ],
              ),
              style: style,
            ),
    );
  }
}
