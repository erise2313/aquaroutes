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
        // A pill with an icon inlines it as a WidgetSpan, so its label lives
        // in rich text. It has to be matched by substring rather than by
        // equality: toPlainText() renders the inlined icon as the
        // object-replacement character, so the pill's plain text is not
        // "ACCREDITED" but "￼ACCREDITED".
        expect(find.textContaining('ACCREDITED', findRichText: true), findsOneWidget, reason: entry.key);
        expect(find.text('PENDING'), findsOneWidget, reason: entry.key);
        expect(tester.takeException(), isNull, reason: entry.key);
      }
    });
  });

  // The owner Dashboard can't be mounted in a test -- it reads Supabase in
  // initState -- but its geometry can. These are the two compositions most
  // likely to break on a phone at large system text: three stat tiles sharing
  // about 100px each, and three peso figures in one row, which have no space
  // to wrap at.
  group('owner dashboard composition', () {
    Widget figure(BuildContext context, String label, String amount, {bool emphasise = false}) {
      final theme = Theme.of(context);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(amount, style: emphasise ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium),
            ),
          ],
        ),
      );
    }

    Widget body() => Builder(
          builder: (context) => Column(
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: PortalStatTile(value: 12, label: 'Pending')),
                  SizedBox(width: 10),
                  Expanded(child: PortalStatTile(value: 148, label: 'Active')),
                  SizedBox(width: 10),
                  Expanded(child: PortalStatTile(value: 2064, label: 'Done')),
                ],
              ),
              const SizedBox(height: 24),
              PortalCard(
                lift: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    figure(context, 'Today', '₱1,240.00', emphasise: true),
                    figure(context, 'This week', '₱18,430.00'),
                    figure(context, 'This month', '₱112,905.00'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PortalCard(
                onTap: () {},
                accent: Colors.teal,
                child: const Row(
                  children: [
                    SizedBox(width: 42, height: 42, child: Icon(Icons.folder_shared_outlined)),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Permit Vault'),
                          Text('Upload business, sanitary, and (if alkaline) technical permits'),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
          ),
        );

    testWidgets('lays out without overflow across widths, text sizes and modes', (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final width in [360.0, 768.0, 1280.0]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            await _pump(tester, theme, body(), size: Size(width, 900), textScale: scale);
            expect(
              tester.takeException(),
              isNull,
              reason: 'dashboard body at ${width}px, text scale $scale',
            );
          }
        }
      }
    });
  });

  // An order card puts a status pill beside the order number and an amount
  // beside the order line, and a peso amount has nowhere to wrap. Neither the
  // Orders screen nor its card can be mounted directly (both need a live
  // Supabase stream), so the composition stands in for them.
  group('owner order card composition', () {
    // Each row is swept on its own: takeException() reports only the error's
    // message, not which widget produced it, so a single all-in-one card
    // would say "a RenderFlex overflowed" without saying which one.
    // Mirrors the Orders screen: the pill sits beside the order number only
    // where there is room for it, and otherwise takes its own line, where its
    // width is bounded and its label can wrap.
    Widget identityRow(BuildContext context) {
      final theme = Theme.of(context);
      final isWide = PortalDensity.of(context).isWide;
      const pill = StatusPill(label: 'OUT FOR DELIVERY', color: Colors.teal);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 40, height: 40, child: Icon(Icons.fiber_new_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #A1B2C3', style: theme.textTheme.titleMedium),
                    Text('Placed at 10:45 AM', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (isWide) ...[const SizedBox(width: 8), pill],
            ],
          ),
          if (!isWide) ...[const SizedBox(height: 10), pill],
        ],
      );
    }

    Widget amountRow(BuildContext context) {
      final theme = Theme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text('3 x Alkaline (Round 5-gal)', style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Text('₱1,240.00', style: theme.textTheme.titleMedium),
        ],
      );
    }

    Widget actionsRow(BuildContext context) {
      return PortalActionRow(
        children: [
          OutlinedButton(onPressed: () {}, child: const Text('Reject')),
          FilledButton(onPressed: () {}, child: const Text('Assign & accept')),
        ],
      );
    }

    final rows = <String, WidgetBuilder>{
      'identity row': identityRow,
      'amount row': amountRow,
      'actions row': actionsRow,
    };

    testWidgets('every row lays out without overflow across widths, text sizes and modes', (tester) async {
      for (final row in rows.entries) {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final width in [360.0, 768.0, 1280.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              await _pump(
                tester,
                theme,
                PortalCard(lift: false, accent: Colors.amber, child: Builder(builder: row.value)),
                size: Size(width, 900),
                textScale: scale,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${row.key} at ${width}px, text scale $scale',
              );
            }
          }
        }
      }
    });
  });

  // The owner Profile's two risky rows: the identity hero, where an avatar
  // sits beside a name and email that have to absorb every text size, and the
  // opening-hours row, which is the two-buttons-in-Expandeds pattern that
  // overflowed on Orders.
  group('owner profile composition', () {
    Widget hero() => Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue, Colors.cyan]),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 30, child: Icon(Icons.storefront)),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Maria Dela Cruz', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Buenavista Water Refilling Station\nowner@buenavista-station.example.com'),
                  ],
                ),
              ),
            ],
          ),
        );

    Widget hours() => PortalActionRow(
          children: [
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Opens 7:00 AM'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.schedule, size: 18),
              label: const Text('Closes 7:00 PM'),
            ),
          ],
        );

    testWidgets('hero and hours lay out without overflow at every width and text size', (tester) async {
      for (final entry in {'hero': hero, 'hours': hours}.entries) {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final width in [360.0, 768.0, 1280.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              await _pump(tester, theme, entry.value(), size: Size(width, 900), textScale: scale);
              expect(
                tester.takeException(),
                isNull,
                reason: '${entry.key} at ${width}px, text scale $scale',
              );
            }
          }
        }
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
