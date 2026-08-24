import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Simple vector shield built from Flutter primitives (ClipPath + Icon) --
/// stands in for a professionally designed logo until a real asset exists.
/// Shared across the guest home, login, and register screens for
/// consistent branding.
class WasaShieldLogo extends StatelessWidget {
  const WasaShieldLogo({super.key, this.size = 100});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _ShieldClipper(),
      child: Container(
        width: size,
        height: size * 1.16,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.primary, AppColors.accent]),
        ),
        child: Icon(Icons.water_drop, color: Colors.white, size: size * 0.48),
      ),
    );
  }
}

class _ShieldClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h * 0.18)
      ..lineTo(w, h * 0.55)
      ..quadraticBezierTo(w, h * 0.85, w / 2, h)
      ..quadraticBezierTo(0, h * 0.85, 0, h * 0.55)
      ..lineTo(0, h * 0.18)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
