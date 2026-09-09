import 'package:flutter/material.dart';

import '../../constants/admin_theme.dart';

/// Pushes an admin screen with the admin theme still applied.
///
/// `AdminNavigation` wraps its tab pages in `Theme(data: AdminTheme.themeData)`,
/// but that wrapper does NOT reach screens opened with `Navigator.push`: a
/// `MaterialPageRoute` builds under the root `Navigator`, above the local
/// `Theme`, so `Theme.of` inside the pushed screen resolves to the root
/// MaterialApp theme instead. (Confirmed with a widget test -- and it's why
/// `showDialog`, which *does* capture ambient themes via
/// `InheritedTheme.capture`, was never affected.) Without this, tapping a
/// station in the navy/gold admin portal opened a generic blue Permit Review
/// screen.
///
/// Use this instead of `MaterialPageRoute` for every push out of an admin
/// screen.
Route<T> adminRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (context) => Theme(data: AdminTheme.themeData, child: child),
  );
}
