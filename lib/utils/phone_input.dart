import 'package:flutter/services.dart';

/// Phone fields accept digits, spaces, "+" and "-" only, so a pasted or
/// mistyped letter never gets in ("Sampaguita St" ended up in the contact
/// number during a test run). Also caps the length at 20.
final List<TextInputFormatter> phoneInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
  LengthLimitingTextInputFormatter(20),
];
