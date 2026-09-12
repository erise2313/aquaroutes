import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a thrown object into something worth showing a customer, a station
/// owner or a driver.
///
/// Screens used to interpolate the raw exception ("Could not load:
/// SocketException: Failed host lookup..."), which tells someone standing in
/// their kitchen nothing about what to do. Server-side messages are the
/// exception: `insert_quick_order` and the product triggers already raise
/// sentences written for the person reading them, so those pass through.
///
/// Deliberately matches on text rather than importing `dart:io`: the same
/// code ships to the website, where `dart:io` doesn't exist and the failure
/// arrives as a `ClientException` or an XMLHttpRequest error instead.
String describeError(Object error) {
  if (error is PostgrestException) return error.message;
  if (error is AuthException) return error.message;
  if (error is StorageException) return error.message;
  if (error is TimeoutException) return 'That took too long. Check your connection and try again.';

  final text = error.toString();
  if (_looksOffline(text)) {
    return 'No internet connection. Check your signal and try again.';
  }
  if (text.contains('FunctionException')) {
    return 'The server could not complete that. Please try again.';
  }
  return 'Something went wrong. Please try again.';
}

bool _looksOffline(String text) {
  const offlineMarkers = [
    'SocketException',
    'Failed host lookup',
    'Network is unreachable',
    'Connection refused',
    'Connection closed',
    'ClientException',
    'XMLHttpRequest',
    'HandshakeException',
  ];
  for (final marker in offlineMarkers) {
    if (text.contains(marker)) return true;
  }
  return false;
}
