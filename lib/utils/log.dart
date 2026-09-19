import 'package:flutter/foundation.dart';

/// Where a swallowed error goes.
///
/// Not debugPrint directly. debugPrint is *not* stripped from release builds
/// -- unlike assert, it keeps writing to logcat on real devices, where any
/// app holding log access can read whatever the exception carried. These
/// calls were scattered across the driver, merchant and admin screens doing
/// exactly that with raw Postgres and auth errors.
///
/// This is also the single seam crash reporting plugs into later. Firebase
/// registers an Android app against its package name and generates a
/// google-services.json keyed to it, so Crashlytics cannot be wired up until
/// the permanent applicationId is decided. When it is, forward to
/// FirebaseCrashlytics.instance.recordError from here and every existing
/// call site starts reporting without another edit.
void logError(String where, Object error, [StackTrace? stack]) {
  if (kDebugMode) {
    debugPrint('[$where] $error');
    if (stack != null) debugPrint('$stack');
  }
}
