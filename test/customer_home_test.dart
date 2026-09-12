import 'package:aquaroute/constants/app_colors.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/widgets/portal/portal.dart';
import 'package:aquaroute/widgets/star_rating.dart';
import 'package:aquaroute/widgets/wave_divider.dart';
import 'package:aquaroute/widgets/web_seal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CustomerHomeScreen itself can't be mounted here -- it reads Supabase in
/// initState -- but its geometry can, and that is what breaks. The hero's
/// eyebrow row, two stat tiles sharing a phone's width, and a station card
/// with an avatar beside an expanded column are the same shapes whose
/// equivalents overflowed three times over in the portals.
final _themes = <String, ThemeData>{
  'light': AppTheme.light,
  'dark': AppTheme.dark,
};

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget child, {
  required Size size,
  required double textScale,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    key: ValueKey('home-${identityHashCode(theme)}'),
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}

Widget _hero() => Builder(
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.accent],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                WebSeal(size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'WATER STATION ASSOCIATION · GENERAL TRIAS',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Every jug, certified.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white, height: 1.15),
            ),
            const SizedBox(height: 10),
            const Text(
              'Order from a station the association has actually reviewed -- '
              'and see the seal before you order a drop.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Order water')),
                OutlinedButton(onPressed: () {}, child: const Text('Find a station')),
              ],
            ),
          ],
        ),
      ),
    );

Widget _stats() => const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: PortalStatTile(value: 12, label: 'Accredited stations', icon: Icons.verified_outlined)),
        SizedBox(width: 10),
        Expanded(child: PortalStatTile(value: 33, label: 'Barangays served', icon: Icons.place_outlined)),
      ],
    );

Widget _stationCard() => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return PortalCard(
          onTap: () {},
          accent: AppColors.seal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 24, child: Icon(Icons.storefront)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Buenavista Water Refilling Station',
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const WebSeal(size: 18),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Buenavista I', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    const StarRatingDisplay(rating: 4.5, reviewCount: 2, size: 13),
                    const SizedBox(height: 6),
                    Text('From ₱25.00', style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

void main() {
  group('customer home composition', () {
    final sections = <String, Widget Function()>{
      'hero': _hero,
      'stats': _stats,
      'station card': _stationCard,
      'wave': () => const WaveDivider(topColor: AppColors.accent, bottomColor: Colors.white),
    };

    testWidgets('lays out without overflow across widths, text sizes and modes', (tester) async {
      for (final section in sections.entries) {
        for (final theme in _themes.entries) {
          for (final width in [360.0, 768.0, 1280.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              await _pump(
                tester,
                theme.value,
                section.value(),
                size: Size(width, 900),
                textScale: scale,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '${section.key} on ${theme.key} at ${width}px, text scale $scale',
              );
            }
          }
        }
      }
    });

    testWidgets('the hero keeps its wording and both calls to action', (tester) async {
      await _pump(tester, AppTheme.light, _hero(), size: const Size(390, 844), textScale: 1.0);

      expect(find.text('Every jug, certified.'), findsOneWidget);
      expect(find.text('Order water'), findsOneWidget);
      expect(find.text('Find a station'), findsOneWidget);
    });
  });
}
