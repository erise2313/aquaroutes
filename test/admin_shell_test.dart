import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/models/app_notification.dart';
import 'package:aquaroute/providers/app_state.dart';
import 'package:aquaroute/screens/admin/admin_route.dart';
import 'package:aquaroute/widgets/admin_page_header.dart';

/// The header carries the notification bell, which reads
/// notificationsProvider -- stubbed here so these layout tests don't need a
/// signed-in Supabase session.
Widget _scoped(Widget home) => ProviderScope(
      overrides: [notificationsProvider.overrideWith((ref) => Stream.value(const <AppNotification>[]))],
      child: MaterialApp(home: home),
    );

/// Guards the three things that make the admin portal feel like one product:
/// pushed screens keep the navy/gold theme, the header adapts to how the page
/// was reached, and the theme's larger type actually takes effect.
void main() {
  testWidgets('adminRoute keeps AdminTheme on pushed screens', (tester) async {
    Color? pushedPrimary;
    // adminRoute resolves the portal's own light/dark choice through a
    // Consumer, so a pushed admin screen needs the app's ProviderScope.
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
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
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(pushedPrimary, AdminTheme.harborBlue,
        reason: 'pushed admin screen should keep the admin theme, not the root blue');
  });

  // The theme toggle, bell and account menu moved up into the portal's
  // shared top bar (widgets/portal/portal_shell.dart), where they are the
  // same three controls on every admin page. The header must not render them
  // too, or each one is offered twice on screen.
  //
  // That they appear in the bar can't be asserted here: PortalShell only
  // builds the bar when kIsWeb, which is a compile-time false under
  // flutter test, and admin is a web-only surface. That half is a browser
  // check.
  testWidgets('header: no duplicate account menu on a tab page, back button when pushed', (tester) async {
    await tester.pumpWidget(_scoped(const Scaffold(body: AdminPageHeader(title: 'Tab Page'))));
    expect(find.byTooltip('Account'), findsNothing, reason: 'the account menu belongs to the top bar now');
    expect(find.byTooltip('Back'), findsNothing);

    // Page-specific actions still belong to the header, and are unaffected.
    await tester.pumpWidget(_scoped(const Scaffold(
      body: AdminPageHeader(
        title: 'Tab Page',
        actions: [Tooltip(message: 'Export', child: Icon(Icons.download_outlined))],
      ),
    )));
    expect(find.byTooltip('Export'), findsOneWidget);

    await tester.pumpWidget(_scoped(Builder(builder: (context) => Scaffold(
      body: ElevatedButton(
        onPressed: () => Navigator.push(context, adminRoute(
          const Scaffold(body: AdminPageHeader(title: 'Pushed Page')))),
        child: const Text('go'),
      ),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget, reason: 'pushed page needs a way back');
    expect(find.byTooltip('Account'), findsNothing);
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
