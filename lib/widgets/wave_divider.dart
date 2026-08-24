import 'package:flutter/material.dart';

/// The website's one structural signature device: a smooth wave transition
/// between two section colors, used at the hero->content seam and between
/// alternating paper/foam sections. One consistent device, reused
/// deliberately, not a different flourish per section.
class WaveDivider extends StatelessWidget {
  const WaveDivider({super.key, required this.topColor, required this.bottomColor, this.height = 48});

  final Color topColor;
  final Color bottomColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _WavePainter(topColor: topColor, bottomColor: bottomColor),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.topColor, required this.bottomColor});

  final Color topColor;
  final Color bottomColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bottomColor);

    final path = Path()..moveTo(0, size.height * 0.5);
    path.cubicTo(
      size.width * 0.25, 0,
      size.width * 0.75, size.height,
      size.width, size.height * 0.5,
    );
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();

    canvas.drawPath(path, Paint()..color = topColor);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.topColor != topColor || oldDelegate.bottomColor != bottomColor;
  }
}
