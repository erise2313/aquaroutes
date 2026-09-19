/// Real paths on the web (/privacy), not fragments (/#/privacy).
///
/// Flutter web defaults to hash routing, and nothing here had ever turned
/// that off -- so every go_router path only resolved after a `#`, and a
/// clean URL like /privacy fell through the Firebase rewrite to index.html
/// and then rendered the home page, because the router reads the fragment
/// rather than the path. Clicking a footer link from there appended the
/// route to whatever path was showing, producing /privacy#/privacy.
///
/// That matters beyond tidiness: Google Play needs a privacy policy URL it
/// can reach directly, and pubspec describes these pages as shareable,
/// bookmarkable and indexable, which a fragment URL is not -- crawlers do
/// not treat #/about as a distinct page.
///
/// It also frees the fragment, which Supabase uses to deliver password
/// recovery tokens (see auth_gate.dart). Route and token were competing for
/// the same part of the URL.
///
/// Web-only: flutter_web_plugins cannot be compiled into the mobile app, so
/// this follows the conditional-export pattern already used for CSV
/// download, and the stub is a no-op off the web.
library;

export 'url_strategy_stub.dart' if (dart.library.js_interop) 'url_strategy_web.dart';
