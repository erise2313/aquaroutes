import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/screens/admin/admin_route.dart';
import 'package:aquaroute/widgets/admin_page_header.dart';

/// Guards the three things that make the admin portal feel like one product:
/// pushed screens keep the navy/gold theme, the header adapts to how the page
/// was reached, and the theme's larger type actually takes effect.
void main() {
  testWidgets('adminRoute keeps AdminTheme on pushed screens', (tester) async {
    Color? pushedPrimary;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: const ColorScheme.light(primary: Color(0xFF0000FF))),
      home: Builder(builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => Navigator.push(context, adminRoute(Builder(builder: (c) {
            pushedPrimary = Theme.of(c).colorScheme.primary;
            return const SizedBox();
          }))),
          child: const Text('go'),
        ),
      )),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(pushedPrimary, AdminTheme.harborBlue,
        reason: 'pushed admin screen should keep the admin theme, not the root blue');
  });

  testWidgets('header: sign-out on a tab page, back button when pushed', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminPageHeader(title: 'Tab Page')),
    ));
    expect(find.byTooltip('Sign Out'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => Navigator.push(context, adminRoute(
            const Scaffold(body: AdminPageHeader(title: 'Pushed Page')))),
          child: const Text('go'),
        ),
      )),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget, reason: 'pushed page needs a way back');
    expect(find.byTooltip('Sign Out'), findsNothing);
  });

  // Regression: ThemeData's textTheme has null fontSizes at construction time
  // (localize merges the geometry in later), so scaling it with
  // .apply(fontSizeFactor:) asserted in debug and silently no-opped in
  // release -- admin lost the larger type it was supposed to get, and only in
  // the builds anyone actually looked at.
  test('AdminTheme scales text up instead of silently dropping the factor', () {
    final textTheme = AdminTheme.themeData.textTheme;
    expect(textTheme.bodyMedium?.fontSize, isNotNull);
    expect(textTheme.bodyMedium!.fontSize!, greaterThan(14.0),
        reason: 'admin type should be larger than Material default for older users');
    for (final style in [
      textTheme.bodyLarge, textTheme.bodySmall, textTheme.labelLarge,
      textTheme.headlineSmall, textTheme.displaySmall,
    ]) {
      expect(style?.fontSize, isNotNull, reason: 'every admin text style needs a real size');
    }
  });
}
