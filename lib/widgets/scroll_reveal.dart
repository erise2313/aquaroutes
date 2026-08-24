import 'package:flutter/material.dart';

/// Fades/slides a section in as it scrolls into view -- unlike FadeSlideIn
/// (which fires once on first paint), this only reveals once the widget is
/// actually visible in the scrollable viewport, so sections further down a
/// long page don't all animate at once on load. No new package: measures
/// its own position against the nearest Scrollable on every scroll update.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({super.key, required this.child, this.offset = 24, this.onVisible});

  final Widget child;
  final double offset;
  final VoidCallback? onVisible;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> {
  bool _visible = false;
  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _scrollable?.position.removeListener(_checkVisibility);
      _scrollable = scrollable;
      _scrollable?.position.addListener(_checkVisibility);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (_visible || !mounted) return;
    final box = context.findRenderObject();
    final scrollableBox = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || scrollableBox is! RenderBox) return;
    final position = box.localToGlobal(Offset.zero, ancestor: scrollableBox);
    if (position.dy < scrollableBox.size.height * 0.92) {
      setState(() => _visible = true);
      widget.onVisible?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.offset / 100),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
