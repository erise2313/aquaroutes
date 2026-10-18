import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aquaroute/constants/app_theme.dart';
import 'package:aquaroute/constants/brand_fonts.dart';
import 'package:aquaroute/constants/brand_tokens.dart';
import 'package:aquaroute/models/order.dart';
import 'package:aquaroute/models/order_status_look.dart';
import 'package:aquaroute/providers/text_size_provider.dart';
import 'package:aquaroute/widgets/portal/status_pill.dart';

/// The legibility pass of October 2026 (UI plan, Phase 1): one legible font,
/// 18 px body with nothing under 16, an in-app text size, and statuses that
/// never rely on colour alone.
void main() {
  // The text-size choice is remembered in SharedPreferences; without the
  // in-memory stand-in its platform channel never answers in a test.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('type', () {
    test('body text is 18 and nothing goes below 16', () {
      for (final b in Brightness.values) {
        final t = AppTheme.themeFor(b).textTheme;
        expect(t.bodyMedium!.fontSize, 18);
        for (final style in [t.bodySmall, t.labelSmall, t.labelMedium, t.labelLarge, t.titleSmall]) {
          expect(style!.fontSize, greaterThanOrEqualTo(16));
        }
      }
    });

    test('every style is Atkinson Hyperlegible, Regular or Bold', () {
      final t = AppTheme.light.textTheme;
      for (final style in [t.bodyMedium, t.bodySmall, t.titleMedium, t.headlineSmall, t.labelLarge]) {
        expect(style!.fontFamily, BrandFonts.family);
        expect([FontWeight.w400, FontWeight.w700], contains(style.fontWeight));
      }
    });

    test('a screen\'s main button is at least 56 tall, others 48', () {
      final theme = AppTheme.light;
      final filled = theme.filledButtonTheme.style!.minimumSize!.resolve({})!;
      final outlined = theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!;
      expect(filled.height, BrandType.minPrimaryTarget);
      expect(outlined.height, BrandType.minTarget);
    });
  });

  group('in-app text size', () {
    testWidgets('multiplies the system text scale rather than replacing it', (tester) async {
      late TextScaler seen;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(textSizeProvider.notifier).set(AppTextSize.large);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: AppTextScale(
            child: Builder(builder: (context) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox();
            }),
          ),
        ),
      ));

      expect(seen.scale(18), closeTo(18 * 1.5 * 1.15, 0.001));
    });

    testWidgets('Normal leaves the system scale untouched', (tester) async {
      late TextScaler seen;
      await tester.pumpWidget(ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: AppTextScale(
            child: Builder(builder: (context) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox();
            }),
          ),
        ),
      ));
      expect(seen.scale(18), closeTo(18 * 1.3, 0.001));
    });
  });

  group('status reads without colour', () {
    test('status colours imply an icon', () {
      expect(StatusPill.iconFor(BrandStatus.success), isNotNull);
      expect(StatusPill.iconFor(BrandStatus.warning), isNotNull);
      expect(StatusPill.iconFor(BrandStatus.danger), isNotNull);
      expect(StatusPill.iconFor(Colors.grey), isNull);
    });

    test('every order status has its own icon', () {
      final icons = {for (final s in OrderStatus.values) OrderStatusLook.of(s).icon};
      expect(icons.length, OrderStatus.values.length);
    });
  });
}
