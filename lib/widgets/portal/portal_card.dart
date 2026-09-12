import 'package:flutter/material.dart';

import '../hover_scale.dart';
import 'portal_density.dart';

/// The one card treatment for the station-owner and admin portals.
///
/// The portals were a mix of stock `Card`s, bare `Container`s and `ListTile`s
/// with different radii, borders and elevations. This is the shape the public
/// site's teaser cards use -- a flat surface, a hairline border, one radius,
/// and a lift on hover for people using a mouse -- expressed in theme tokens
/// so it works in light and dark under both AppTheme and AdminTheme.
class PortalCard extends StatelessWidget {
  const PortalCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accent,
    this.lift = true,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  /// A thin colour bar down the leading edge, for rows whose status is worth
  /// seeing before reading them.
  final Color? accent;

  /// Hover lift. Turn it off inside a long scrolling list, where the movement
  /// becomes noise rather than feedback.
  final bool lift;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final density = PortalDensity.of(context);

    final body = Padding(
      padding: padding ?? density.cardPadding,
      child: child,
    );

    // The accent is painted inside the card, not as a border side: a border
    // with one differently-coloured edge can't be given a radius ("a
    // borderRadius can only be given on borders with uniform colors"), and a
    // stretched Row asks its children for an unbounded height, which asserts
    // as soon as a card sits in a scrolling column -- which is how every
    // portal screen uses it. A Positioned strip stretches to whatever height
    // the content settles at, and demands nothing of it.
    final surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          onTap == null
              ? Padding(padding: EdgeInsets.only(left: accent == null ? 0 : 4), child: body)
              : InkWell(
                  onTap: onTap,
                  child: Padding(padding: EdgeInsets.only(left: accent == null ? 0 : 4), child: body),
                ),
          if (accent != null)
            Positioned(top: 0, bottom: 0, left: 0, width: 4, child: IgnorePointer(child: ColoredBox(color: accent!))),
        ],
      ),
    );

    return lift ? HoverScale(scale: 1.01, child: surface) : surface;
  }
}
