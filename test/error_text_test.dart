import 'dart:async';

import 'package:aquaroute/utils/error_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('server messages pass through -- they are already written for people', () {
    expect(
      describeError(PostgrestException(message: 'This station does not offer alkaline water.')),
      'This station does not offer alkaline water.',
    );
    expect(describeError(AuthException('Invalid login credentials')), 'Invalid login credentials');
  });

  test('a dropped connection says so, on phone and on the web', () {
    const phone = "SocketException: Failed host lookup: 'kdptnxvspqunjngaduok.supabase.co'";
    const web = 'ClientException: XMLHttpRequest error.';
    expect(describeError(Exception(phone)), contains('No internet connection'));
    expect(describeError(Exception(web)), contains('No internet connection'));
  });

  test('a timeout is its own message', () {
    expect(describeError(TimeoutException('x')), contains('took too long'));
  });

  test('anything else gets a plain apology, never a stack trace', () {
    final message = describeError(StateError('Bad state: _dependents.isEmpty'));
    expect(message, 'Something went wrong. Please try again.');
    expect(message, isNot(contains('_dependents')));
  });
}
