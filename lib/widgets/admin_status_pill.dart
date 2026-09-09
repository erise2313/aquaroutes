import 'package:flutter/material.dart';

/// Small colored status label used across every admin review screen
/// (Station Accreditation, Permit Review, Worker Clearance, User
/// Management) -- one shared implementation instead of a pill `Container`
/// copy-pasted per screen, so the same semantic state (accredited/cleared
/// = green, pending = amber, flagged/rejected = red) always renders
/// identically wherever it shows up.
class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
    );
  }
}
