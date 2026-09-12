import 'package:flutter/material.dart';

import '../count_up_text.dart';
import '../status_callout.dart';

/// The public site's stat card, for the portals.
///
/// A large number set in the display face, counting up the first time it
/// appears, with its label beneath -- the treatment the home page uses for
/// "accredited stations" and "barangays served". The owner dashboard and
/// admin Overview previously showed the same figures as flat coloured boxes.
class PortalStatTile extends StatelessWidget {
  const PortalStatTile({
    super.key,
    required this.value,
    required this.label,
    this.accent,
    this.icon,
    this.caption,
    this.onTap,
    this.animate = true,
  });

  /// Shown as-is when [formatted] would lose meaning (money, for instance):
  /// pass the number for counting, or use [PortalStatTile.text].
  final int value;
  final String label;

  /// Tints the tile and the number. Defaults to the theme's primary.
  final Color? accent;
  final IconData? icon;

  /// A smaller line under the label -- "delivered today", "awaiting review".
  final String? caption;

  final VoidCallback? onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = accent ?? theme.colorScheme.primary;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: CountUpText(
                value: value,
                start: animate,
                style: theme.textTheme.headlineMedium!.copyWith(
                  color: StatusTint.onTint(context, tone),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (icon != null) Icon(icon, color: StatusTint.onTint(context, tone), size: 22),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurface)),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: StatusTint.surface(context, tone),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StatusTint.border(context, tone)),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: const EdgeInsets.all(18), child: content)
          : InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: content)),
    );
  }
}
