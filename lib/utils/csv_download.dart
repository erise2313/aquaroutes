/// Saves a CSV where that's possible -- the browser, which is where the
/// admin portal runs. On the mobile app the stub returns false and the
/// caller explains that exporting lives in the web portal.
library;

export 'csv_download_stub.dart' if (dart.library.js_interop) 'csv_download_web.dart';
