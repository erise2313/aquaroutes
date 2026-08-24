import 'package:flutter/material.dart';

/// Lightweight first-paint entrance animation -- fades in and slides up
/// slightly. Pass an incremental [delay] per item in a list to stagger a
/// group of siblings. Not scroll-linked (fires once on first build), which
/// keeps this dependency-free.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.offset = 16,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + delay,
      curve: Interval(
        (delay.inMilliseconds / (duration + delay).inMilliseconds).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOut,
      ),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, (1 - value) * offset), child: child),
        );
      },
      child: child,
    );
  }
}
