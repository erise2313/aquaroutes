import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/widgets/written_address_fields.dart';

void main() {
  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('address fields fit at $width px, text x$scale', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 1400), textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: WrittenAddressFields(
                  street: TextEditingController(text: 'Blk 3 Lot 5, Sampaguita St., Greenwoods Executive Village Phase 2'),
                  city: TextEditingController(),
                  landmark: TextEditingController(),
                  barangay: 'Pasong Camachile II',
                  onBarangayChanged: (_) {},
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // City defaults to General Trias.
        expect(find.text('General Trias'), findsOneWidget);
        expect(find.text('Pasong Camachile II'), findsOneWidget);
      });
    }
  }
}
