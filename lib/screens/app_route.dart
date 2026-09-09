import 'package:flutter/material.dart';

import '../constants/app_theme.dart';

/// Pushes a merchant or customer screen with the app theme still applied.
///
/// The shells (MerchantNavigation, PublicHomeScreen) wrap their pages in
/// `Theme(data: AppTheme.light)`, but that wrapper does NOT reach screens
/// opened with `Navigator.push`: a `MaterialPageRoute` builds under the root
/// `Navigator`, above the local `Theme`, so `Theme.of` inside the pushed
/// screen resolves to the root MaterialApp theme instead. (`showDialog` is
/// unaffected -- it captures ambient themes via `InheritedTheme.capture`.)
///
/// This is the same defect that made pushed admin screens render generic
/// blue inside the navy portal, fixed the same way -- see
/// screens/admin/admin_route.dart, and the widget test in
/// test/admin_shell_test.dart that pins the behaviour down.
///
/// It matters more here than it looks: the root theme can be the website's
/// *dark* theme, so without this a pushed merchant screen would render its
/// white cards and grey text on a dark page.
///
/// Use this instead of `MaterialPageRoute` for every push out of a merchant
/// or customer screen.
Route<T> appRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (context) => Theme(data: AppTheme.light, child: child),
  );
}

/// Pushes a screen carrying whatever theme was ambient at the push site.
///
/// For widgets shared across surfaces that don't agree on a theme --
/// `screens/public/bulletin_feed.dart` is embedded in the admin portal, the
/// merchant portal, the driver dashboard, the customer app *and* the public
/// website's news page. Pinning its pushes to [AppTheme] would hand a
/// dark-mode website visitor a light login screen; leaving them as a bare
/// `MaterialPageRoute` would drop them to the root theme instead. Capturing
/// gives each host what it actually has.
///
/// This is the same mechanism `showDialog` uses, which is why dialogs never
/// suffered the lost-theme bug that pushed routes do.
Route<T> ambientRoute<T>(BuildContext context, Widget child) {
  final themed = InheritedTheme.captureAll(context, child);
  return MaterialPageRoute<T>(builder: (_) => themed);
}
