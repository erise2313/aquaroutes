import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands the browser a CSV to save, by building a Blob and clicking a
/// generated link.
///
/// The leading byte-order mark is deliberate: without it Excel opens a
/// UTF-8 CSV as Latin-1 and turns every peso sign and ñ into mojibake,
/// which is exactly what an association secretary would hit first.
bool downloadCsv(String filename, String content) {
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
