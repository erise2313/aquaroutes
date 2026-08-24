import 'package:flutter/material.dart';

/// Animates a number counting up from 0 to [value] once [start] flips true
/// (driven externally, typically by ScrollReveal.onVisible) -- stays at 0
/// until then rather than free-running on first build, so it only plays
/// once the number actually scrolls into view.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, required this.start, required this.style});

  final int value;
  final bool start;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: start ? value : 0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) => Text('$animatedValue', style: style),
    );
  }
}
