import 'package:flutter/material.dart';

/// Wraps a widget (typically a button) with a subtle hover scale-up, the
/// same micro-interaction already used by station/benefit cards, extended
/// here to CTA buttons for consistency.
class HoverScale extends StatefulWidget {
  const HoverScale({super.key, required this.child, this.scale = 1.04});

  final Widget child;
  final double scale;

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: reduceMotion
          ? widget.child
          : AnimatedScale(
              scale: _hovering ? widget.scale : 1.0,
              duration: const Duration(milliseconds: 150),
              child: widget.child,
            ),
    );
  }
}
