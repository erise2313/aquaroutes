/// The browser's history, where there is one -- the website. In the app the
/// stub does nothing.
library;

export 'browser_history_stub.dart' if (dart.library.js_interop) 'browser_history_web.dart';
