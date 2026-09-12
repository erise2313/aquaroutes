import 'package:flutter/material.dart';

import 'portal_density.dart';

/// A titled block, with the spacing rhythm the public site uses between
/// sections.
///
/// The portals previously ran headings together as inline
/// `TextStyle(fontSize: 20, fontWeight: bold)` with ad-hoc `SizedBox`es
/// between them, which is most of why they read as a list of widgets rather
/// than a designed page. The title here comes from the theme's display face.
class PortalSection extends StatelessWidget {
  const PortalSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.dense = false,
  });

  final String title;
  final Widget child;
  final String? subtitle;

  /// A trailing action beside the heading -- "View all", "Add", "Export".
  final Widget? action;

  /// Tighter spacing, for sections stacked inside a card.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = PortalDensity.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
        SizedBox(height: dense ? 8 : density.gap),
        child,
      ],
    );
  }

  /// The gap to leave before the next section.
  static double gapAfter(BuildContext context) => PortalDensity.of(context).sectionGap;
}
