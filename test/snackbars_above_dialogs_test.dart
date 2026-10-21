import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/main.dart' show SnackBarsAboveDialogs;

void main() {
  Future<void> openDialogAndWarn(WidgetTester tester, {required bool wrapped}) async {
    await tester.pumpWidget(MaterialApp(
      builder: wrapped ? (context, child) => SnackBarsAboveDialogs(child: child!) : null,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                content: const SizedBox(width: 300, height: 400),
                actions: [
                  TextButton(
                    onPressed: () => ScaffoldMessenger.of(dialogContext)
                        .showSnackBar(const SnackBar(content: Text('Choose what went wrong'))),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('a SnackBar raised from a dialog is drawn on top of it', (tester) async {
    await openDialogAndWarn(tester, wrapped: true);
    expect(find.text('Choose what went wrong').hitTestable(), findsOneWidget);
  });

  testWidgets('without the wrapper it was hidden under the dialog backdrop', (tester) async {
    await openDialogAndWarn(tester, wrapped: false);
    expect(find.text('Choose what went wrong'), findsOneWidget);
    expect(find.text('Choose what went wrong').hitTestable(), findsNothing);
  });
}
