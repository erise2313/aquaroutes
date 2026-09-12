import 'package:aquaroute/models/app_notification.dart';
import 'package:aquaroute/models/membership.dart';
import 'package:aquaroute/services/account_service.dart';
import 'package:aquaroute/widgets/bulletin_comments.dart';
import 'package:aquaroute/widgets/change_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validateNewPassword uses the registration rule', () {
    expect(validateNewPassword(''), isNotNull);
    expect(validateNewPassword(null), isNotNull);
    expect(validateNewPassword('1234567'), isNotNull);
    expect(validateNewPassword('12345678'), isNull);
  });

  test('only customers delete their own account; everyone else requests it', () {
    expect(deletionModeFor(AppRole.publicConsumer), DeletionMode.selfService);
    expect(deletionModeFor(null), DeletionMode.selfService);
    expect(deletionModeFor(AppRole.stationOwner), DeletionMode.request);
    expect(deletionModeFor(AppRole.driver), DeletionMode.request);
    expect(deletionModeFor(AppRole.wasaAdmin), DeletionMode.request);
  });

  test('canDeleteComment: the author or an admin, never a signed-out visitor', () {
    expect(canDeleteComment(authorId: 'a', viewerId: 'a', viewerIsAdmin: false), isTrue);
    expect(canDeleteComment(authorId: 'a', viewerId: 'b', viewerIsAdmin: false), isFalse);
    expect(canDeleteComment(authorId: 'a', viewerId: 'b', viewerIsAdmin: true), isTrue);
    expect(canDeleteComment(authorId: 'a', viewerId: null, viewerIsAdmin: true), isFalse);
  });

  test('notificationAge reads as a person would say it', () {
    final now = DateTime(2026, 9, 12, 12, 0);
    expect(notificationAge(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
    expect(notificationAge(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
    expect(notificationAge(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(notificationAge(now.subtract(const Duration(days: 2)), now: now), '2d ago');
    expect(notificationAge(DateTime(2026, 8, 1), now: now), '1/8/2026');
  });

  group('ChangePasswordDialog', () {
    Future<List<bool?>> pumpDialog(WidgetTester tester, Future<void> Function(String, String) onSubmit) async {
      final results = <bool?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showDialog<bool>(context: context, builder: (_) => ChangePasswordDialog(onSubmit: onSubmit)),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    Future<void> fill(WidgetTester tester, String current, String next, String confirm) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), current);
      await tester.enterText(fields.at(1), next);
      await tester.enterText(fields.at(2), confirm);
    }

    testWidgets('cancel closes without calling the server', (tester) async {
      var calls = 0;
      final results = await pumpDialog(tester, (_, _) async => calls++);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(calls, 0);
      expect(tester.takeException(), isNull); // controllers outlive the exit animation
    });

    testWidgets('mismatched confirmation is caught before submitting', (tester) async {
      var calls = 0;
      await pumpDialog(tester, (_, _) async => calls++);
      await fill(tester, 'oldpassword', 'newpassword1', 'newpassword2');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text("The passwords don't match"), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('a server rejection is shown in the dialog', (tester) async {
      await pumpDialog(tester, (_, _) async => throw const AccountException('Your current password is incorrect.'));
      await fill(tester, 'wrongpassword', 'newpassword1', 'newpassword1');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
    });

    testWidgets('success pops with true', (tester) async {
      String? sentCurrent, sentNext;
      final results = await pumpDialog(tester, (current, next) async {
        sentCurrent = current;
        sentNext = next;
      });
      await fill(tester, 'oldpassword', 'newpassword1', 'newpassword1');
      await tester.tap(find.widgetWithText(FilledButton, 'Change password'));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(sentCurrent, 'oldpassword');
      expect(sentNext, 'newpassword1');
    });
  });
}
