import 'package:flutter_web_plugins/url_strategy.dart';

/// Drops the `#` from every route. Requires the host to serve index.html for
/// unknown paths, which firebase.json already does for both targets.
void useRealUrls() => usePathUrlStrategy();
