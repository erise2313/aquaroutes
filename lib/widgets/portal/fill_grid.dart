import 'package:flutter/material.dart';

/// Tiles laid out in as many equal columns as fit, each stretched to fill
/// its share of the row.
///
/// Stat tiles used to sit in a Wrap with a fixed width each (200 or 220 px).
/// On a 360 px phone only one fitted per row and it covered barely half the
/// screen, leaving the rest empty; on a tablet the last row was ragged. Here
/// a tile is never narrower than [minTileWidth] and never leaves a gap.
class FillGrid extends StatelessWidget {
  const FillGrid({
    super.key,
    required this.children,
    this.minTileWidth = 150,
    this.spacing = 12,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final fit = ((width + spacing) / (minTileWidth + spacing)).floor();
      final columns = fit.clamp(1, maxColumns).clamp(1, children.isEmpty ? 1 : children.length);
      final tileWidth = (width - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: tileWidth, child: child)],
      );
    });
  }
}
