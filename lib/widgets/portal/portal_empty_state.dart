import 'package:flutter/material.dart';

/// "There's nothing here, and here's what to do about it."
///
/// Admin had four near-identical private `_emptyState` helpers and the owner
/// screens had their own variants, all slightly different. One shape means an
/// empty list reads the same wherever it appears -- and always says why it's
/// empty rather than just showing a grey line.
class PortalEmptyState extends StatelessWidget {
  const PortalEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Inside a ListView the height is unbounded, so it simply
        // shrink-wraps -- wrapping it in a scroll view there would assert.
        if (!constraints.hasBoundedHeight) return content;

        // Given a real box -- a whole screen, usually -- it centres, and
        // scrolls rather than overflowing when the box is shorter than the
        // content. A phone held sideways is exactly that case, and it
        // overflowed by 174px before this.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
