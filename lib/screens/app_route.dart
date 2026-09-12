import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_theme_provider.dart';

/// Pushes a merchant or customer screen with the app theme still applied.
///
/// The shells (MerchantNavigation, PublicHomeScreen) wrap their pages in the
/// app theme, but that wrapper does NOT reach screens opened with
/// `Navigator.push`: a `MaterialPageRoute` builds under the root
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
/// theme, so without this a pushed merchant screen would render its cards
/// and text against the wrong background entirely.
///
/// The theme is resolved through a `Consumer` rather than pinned, so a
/// pushed screen follows the phone's light/dark setting (and the override in
/// Account settings) exactly like the screen that pushed it.
Route<T> appRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (context) => Consumer(
      builder: (context, ref, _) => Theme(
        data: appThemeDataFor(ref.watch(appThemeProvider), MediaQuery.platformBrightnessOf(context)),
        child: child,
      ),
    ),
  );
}

/// Pushes a screen carrying whatever theme was ambient at the push site.
///
/// For widgets shared across surfaces that don't agree on a theme --
/// `screens/public/bulletin_feed.dart` is embedded in the admin portal, the
/// merchant portal, the driver dashboard, the customer app *and* the public
/// website's news page. Pinning its pushes to [appRoute] would hand a
/// dark-mode website visitor the app's theme; leaving them as a bare
/// `MaterialPageRoute` would drop them to the root theme instead. Capturing
/// gives each host what it actually has.
///
/// This is the same mechanism `showDialog` uses, which is why dialogs never
/// suffered the lost-theme bug that pushed routes do.
Route<T> ambientRoute<T>(BuildContext context, Widget child) {
  final themed = InheritedTheme.captureAll(context, child);
  return MaterialPageRoute<T>(builder: (_) => themed);
}
