import 'package:flutter/material.dart';

/// A row of buttons that stops being a row when the buttons no longer fit.
///
/// Two buttons side by side in `Expanded`s is the portals' usual decision
/// pattern -- Reject / Assign, Decline / Approve, Cancel / Save. On a 360px
/// phone at 200% system text each one gets about 158px while a label like
/// "Assign & accept" needs closer to 260px, so the row overflows: the text
/// inside a button has no room to shrink and `Expanded` will not give it any.
///
/// Below the width the buttons actually need, they stack full-width instead,
/// which is what a phone wants anyway.
class PortalActionRow extends StatelessWidget {
  const PortalActionRow({
    super.key,
    required this.children,
    this.minButtonWidth = 150,
    this.gap = 8,
  });

  final List<Widget> children;

  /// The width one button needs at normal text size. Scaled by the viewer's
  /// text setting before it's compared with the space available.
  final double minButtonWidth;

  final double gap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) {
      return Row(children: [Expanded(child: children.single)]);
    }

    // The ratio the viewer's text setting applies, so a button that fits at
    // 100% is not assumed to fit at 200%.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final needed = minButtonWidth * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - gap * (children.length - 1);
        final fits = constraints.hasBoundedWidth && available / children.length >= needed;

        if (fits) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: children[i]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      },
    );
  }
}
