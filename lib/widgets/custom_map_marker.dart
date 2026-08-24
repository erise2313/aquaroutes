import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum MapPinKind { station, stationAlkaline, driver, currentStop, queuedStop, deliveryAddress }

/// Shared marker widget for all flutter_map screens (station map, tracking,
/// driver dashboard, location picker), replacing the ad-hoc inline
/// `Marker(...)` construction duplicated across each screen previously.
/// Alkaline-offering stations get an animated glowing cyan/purple pulse
/// (spec 4D) instead of a plain pin.
class MapPin extends StatelessWidget {
  const MapPin({super.key, required this.kind, this.isAccredited = false});

  final MapPinKind kind;
  final bool isAccredited;

  @override
  Widget build(BuildContext context) {
    if (kind == MapPinKind.stationAlkaline) {
      return _PulsingAlkalinePin(isAccredited: isAccredited);
    }

    final (color, icon) = switch (kind) {
      MapPinKind.station => (Colors.blue, Icons.storefront),
      MapPinKind.driver => (Colors.green, Icons.local_shipping),
      MapPinKind.currentStop => (Colors.red, Icons.local_shipping),
      MapPinKind.queuedStop => (Colors.orange, Icons.local_shipping),
      MapPinKind.deliveryAddress => (Colors.green, Icons.location_on),
      MapPinKind.stationAlkaline => (Colors.cyan, Icons.storefront), // unreachable
    };

    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _PulsingAlkalinePin extends StatefulWidget {
  const _PulsingAlkalinePin({required this.isAccredited});

  final bool isAccredited;

  @override
  State<_PulsingAlkalinePin> createState() => _PulsingAlkalinePinState();
}

class _PulsingAlkalinePinState extends State<_PulsingAlkalinePin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glowColor = widget.isAccredited ? AppColors.alkalineGlowPurple : AppColors.alkalineGlowCyan;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final scale = 1.0 + (t * 0.6);
        final opacity = (1.0 - t).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withValues(alpha: opacity * 0.5),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: glowColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: glowColor.withValues(alpha: 0.8), blurRadius: 8)],
        ),
        child: const Icon(Icons.water_drop, color: Colors.white, size: 16),
      ),
    );
  }
}
