import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_theme_provider.dart';


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
    builder: (context) => Consumer(
      builder: (context, ref, _) => Theme(
        data: adminThemeDataFor(ref.watch(adminThemeProvider)),
        // Sidebar sections are bare Columns that rely on the shell's
        // Scaffold. Opened on their own (a dashboard shortcut on a phone)
        // they had none, so they drew on black: a grey header and dark
        // labels nobody could read. A screen with its own Scaffold is
        // unaffected; SafeArea keeps the header out of the status bar.
        child: Scaffold(body: SafeArea(bottom: false, child: child)),
      ),
    ),
  );
}
