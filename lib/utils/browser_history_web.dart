import 'package:web/web.dart' as web;

/// Steps the browser back one entry, as its own Back button would.
void browserHistoryBack() => web.window.history.back();
