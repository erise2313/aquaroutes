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

  /// The accent as text or an icon on that tint.
  ///
  /// This used to return the accent unchanged in light mode and a flat 45%
  /// lerp toward white in dark -- both assumed a contrast they never checked.
  /// The association's amber (#F9A825) failed badly: amber text on a 10%
  /// amber wash over a near-white card measured 1.84:1, so every PENDING,
  /// RENEWAL DUE and IDLE label in both portals was close to unreadable.
  ///
  /// So it now moves the accent toward black (light) or white (dark) until it
  /// actually clears the target against the tint as composited over the
  /// surface beneath. Colours that already passed -- the deep green and red --
  /// barely move; the amber darkens until it reads. Any accent added later is
  /// corrected the same way rather than needing to be hand-checked.
  static Color onTint(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = Color.alphaBlend(surface(context, accent), theme.colorScheme.surface);
    final toward = isDark ? Colors.white : Colors.black;

    var candidate = isDark ? Color.lerp(accent, Colors.white, 0.45)! : accent;
    // 12 steps of 5% is enough to carry any hue to the target without ever
    // reaching the flat black or white that would throw the meaning away.
    for (var i = 0; i < 12; i++) {
      if (_contrast(candidate, background) >= _targetContrast) return candidate;
      candidate = Color.lerp(candidate, toward, 0.05)!;
    }
    return candidate;
  }

  /// WCAG AA for normal-size text. Pill labels are small and bold, so this is
  /// the stricter of the two thresholds, deliberately.
  static const _targetContrast = 4.5;

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
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
