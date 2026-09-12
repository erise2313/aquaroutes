import 'package:flutter/material.dart';

/// A tinted callout that survives dark mode.
///
/// These were written as `Colors.amber.shade50` and friends -- a near-white
/// wash that assumed near-black text. Once the app gained dark mode, the
/// text turned light and the callouts became unreadable: the pinned bulletin
/// card, the accreditation banners, the permit-renewal warning.
///
/// A translucent tint over whatever surface is underneath keeps the colour's
/// meaning (amber warns, green confirms) while the text stays whatever the
/// theme says it should be.
class StatusTint {
  StatusTint._();

  /// Background fill. Slightly stronger on dark, where a 10% wash over navy
  /// all but disappears.
  static Color surface(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return accent.withValues(alpha: isDark ? 0.18 : 0.10);
  }

  static Color border(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return accent.withValues(alpha: isDark ? 0.45 : 0.30);
  }

  /// The accent as text or an icon on that tint -- lightened on dark so a
  /// deep amber or green doesn't sink into the background.
  static Color onTint(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return accent;
    return Color.lerp(accent, Colors.white, 0.45)!;
  }
}

/// A boxed message in one of the status colours -- the shape used by the
/// accreditation banners, the "no products yet" prompt and the renewal
/// warning, so they all read the same way in both modes.
class StatusCallout extends StatelessWidget {
  const StatusCallout({
    super.key,
    required this.accent,
    required this.icon,
    required this.title,
    this.message,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: StatusTint.onTint(context, accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: StatusTint.surface(context, accent),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatusTint.border(context, accent)),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
