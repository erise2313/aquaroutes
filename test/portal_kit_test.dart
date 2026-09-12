import 'package:aquaroute/constants/admin_theme.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/widgets/portal/portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every kit widget has to survive four combinations: two portals, two modes.
/// The portals' themes are separate objects (AppTheme for the station owner,
/// AdminTheme for WASA), and the kit reads only Theme.of(context), so this is
/// what proves that claim.
final _themes = <String, ThemeData>{
  'owner light': AppTheme.light,
  'owner dark': AppTheme.dark,
  'admin light': AdminTheme.light,
  'admin dark': AdminTheme.dark,
};

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget child, {
  Size size = const Size(1280, 900),
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    // A new key per theme forces a fresh tree instead of letting MaterialApp
    // animate from the previous one. AppTheme and AdminTheme build their text
    // themes differently (AdminTheme merges the englishLike geometry, so its
    // styles carry inherit: false), and TextStyle.lerp refuses to interpolate
    // across that. Nothing animates between the two families at runtime --
    // the root app only ever crossfades AppTheme light <-> dark, and the
    // admin toggle swaps a plain Theme -- so this is the harness's problem to
    // solve, not the themes'.
    key: ValueKey('portal-kit-${identityHashCode(theme)}'),
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('PortalPageHeader', () {
    testWidgets('shows its eyebrow, title and subtitle in every theme', (tester) async {
      for (final entry in _themes.entries) {
        await _pump(tester, entry.value, const PortalPageHeader(
          eyebrow: 'Your station',
          title: 'Station Dashboard',
          subtitle: 'Buenavista Water Refilling Station',
        ));
        expect(find.text('YOUR STATION'), findsOneWidget, reason: entry.key);
        expect(find.text('Station Dashboard'), findsOneWidget, reason: entry.key);
        expect(find.text('Buenavista Water Refilling Station'), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('lays out without overflow across widths and text sizes', (tester) async {
      for (final width in [360.0, 768.0, 1280.0]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          await _pump(
            tester,
            AppTheme.light,
            PortalPageHeader(
              eyebrow: 'Association',
              title: 'Station Accreditation',
              subtitle: 'Every registered station, by current status',
              actions: [
                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.download_outlined), label: const Text('Export')),
              ],
            ),
            size: Size(width, 900),
            textScale: scale,
          );
          expect(tester.takeException(), isNull, reason: 'header at ${width}px, text scale $scale');
        }
      }
    });
  });

  group('PortalStatTile', () {
    testWidgets('counts up to its value and keeps the label readable', (tester) async {
      for (final entry in _themes.entries) {
        await _pump(tester, entry.value, const SizedBox(
          width: 260,
          child: PortalStatTile(value: 12, label: 'Pending', caption: 'awaiting a driver'),
        ));
        expect(find.text('12'), findsOneWidget, reason: entry.key);
        expect(find.text('Pending'), findsOneWidget, reason: entry.key);
        expect(find.text('awaiting a driver'), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('survives a long label at 200% text', (tester) async {
      await _pump(
        tester,
        AppTheme.dark,
        const SizedBox(width: 200, child: PortalStatTile(value: 1234, label: 'Orders delivered this month')),
        size: const Size(360, 900),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PortalCard and PortalSection', () {
    testWidgets('a titled section renders its action and child', (tester) async {
      for (final entry in _themes.entries) {
        await _pump(tester, entry.value, PortalSection(
          title: 'Sales',
          subtitle: 'Delivered orders only',
          action: TextButton(onPressed: () {}, child: const Text('View all')),
          child: const PortalCard(child: Text('₱1,240.00')),
        ));
        expect(find.text('Sales'), findsOneWidget, reason: entry.key);
        expect(find.text('View all'), findsOneWidget, reason: entry.key);
        expect(find.text('₱1,240.00'), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('a tappable card reports taps', (tester) async {
      var taps = 0;
      await _pump(tester, AppTheme.light, PortalCard(
        onTap: () => taps++,
        accent: Colors.orange,
        child: const Text('Permit Vault'),
      ));
      await tester.tap(find.text('Permit Vault'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('PortalEmptyState and StatusPill', () {
    testWidgets('an empty state explains itself and offers its action', (tester) async {
      for (final entry in _themes.entries) {
        await _pump(tester, entry.value, PortalEmptyState(
          icon: Icons.sell_outlined,
          title: 'No products yet',
          message: 'Customers cannot order until you list one.',
          action: FilledButton(onPressed: () {}, child: const Text('Add product')),
        ));
        expect(find.text('No products yet'), findsOneWidget, reason: entry.key);
        expect(find.text('Add product'), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('status pills render in every theme, with or without an icon', (tester) async {
      for (final entry in _themes.entries) {
        await _pump(tester, entry.value, const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusPill(label: 'ACCREDITED', color: Colors.green, icon: Icons.verified),
            SizedBox(width: 8),
            StatusPill(label: 'PENDING', color: Colors.amber),
          ],
        ));
        expect(find.text('ACCREDITED'), findsOneWidget, reason: entry.key);
        expect(find.text('PENDING'), findsOneWidget, reason: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
      }
    });
  });

  group('PortalDensity', () {
    test('phone and desk get different spacing, from one decision', () {
      final phone = PortalDensity.forWidth(360);
      final desk = PortalDensity.forWidth(1280);

      expect(phone.isWide, isFalse);
      expect(desk.isWide, isTrue);
      expect(desk.pagePadding.horizontal, greaterThan(phone.pagePadding.horizontal));
      expect(desk.sectionGap, greaterThan(phone.sectionGap));
    });

    test('columns fit the usable width and never drop below one', () {
      expect(PortalDensity.forWidth(360).columnsFor(260), 1);
      expect(PortalDensity.forWidth(1280).columnsFor(260), greaterThan(2));
      expect(PortalDensity.forWidth(200).columnsFor(600), 1);
    });
  });
}
