import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Floating "back to top" button that fades in once [controller] has
/// scrolled past [showAfter] pixels. Wrap the page's Scaffold body in a
/// Stack and place this as the last child, positioned bottom-right.
class BackToTopButton extends StatefulWidget {
  const BackToTopButton({super.key, required this.controller, this.showAfter = 400});

  final ScrollController controller;
  final double showAfter;

  @override
  State<BackToTopButton> createState() => _BackToTopButtonState();
}

class _BackToTopButtonState extends State<BackToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = widget.controller.offset > widget.showAfter;
    if (shouldShow != _visible) {
      setState(() => _visible = shouldShow);
    }
  }

  void _scrollToTop() {
    widget.controller.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      bottom: 24,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_visible,
          child: FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed: _scrollToTop,
            tooltip: 'Back to top',
            child: const Icon(Icons.arrow_upward, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
