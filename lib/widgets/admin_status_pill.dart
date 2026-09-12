import 'package:flutter/material.dart';

import 'portal/status_pill.dart';

/// Small colored status label used across every admin review screen
/// (Station Accreditation, Permit Review, Worker Clearance, User
/// Management).
///
/// Now a thin wrapper over the shared [StatusPill], so admin and the station
/// owner portal render the same semantic state the same way -- and so the
/// pills pick up the dark-mode-aware tint without touching every call site.
/// New code should use [StatusPill] directly.
class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => StatusPill(label: label, color: color);
}
