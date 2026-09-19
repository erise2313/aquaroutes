import 'package:aquaroute/constants/portal_build.dart';
import 'package:aquaroute/screens/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The admin portal (--dart-define=PORTAL=admin) is staff-only: WASA creates
/// those accounts, so the shared login screen must not offer registration or
/// guest browsing there.
///
/// Note what this can and cannot check. kIsAdminPortalBuild is a compile-time
/// constant and is always false under `flutter test`, the same way kIsWeb is,
/// so the admin branch cannot be exercised from here at all. What these lock
/// is the other half of the condition -- that the app and the public website
/// keep both links -- so inverting or dropping the guard fails the suite.
void main() {
  testWidgets('the test build is not the admin portal', (tester) async {
    expect(kIsAdminPortalBuild, isFalse);
  });

  testWidgets('a normal build still offers registration and guest browsing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    expect(find.textContaining('Register here', findRichText: true), findsOneWidget);
    expect(find.text('Continue browsing as guest'), findsOneWidget);
  });
}
