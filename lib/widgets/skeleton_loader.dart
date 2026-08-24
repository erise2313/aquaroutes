import 'package:flutter/material.dart';

/// Simple pulsing placeholder block for loading states -- avoids pulling in
/// a shimmer package for a one-off pulse effect.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({super.key, this.width, this.height = 16, this.borderRadius = 6});

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.3),
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(widget.borderRadius)),
      ),
    );
  }
}

/// A skeleton placeholder shaped like a typical content card (used by
/// News/Stations/Homepage while data loads).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBlock(width: 140, height: 12),
            const SizedBox(height: 10),
            const SkeletonBlock(height: 14),
            const SizedBox(height: 8),
            SkeletonBlock(width: double.infinity, height: height - 60),
          ],
        ),
      ),
    );
  }
}

/// A column of [count] skeleton cards, for list-shaped loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.cardHeight = 88});

  final int count;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => SkeletonCard(height: cardHeight)),
    );
  }
}
