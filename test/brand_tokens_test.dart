import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/constants/admin_palette.dart';
import 'package:aquaroute/constants/app_palette.dart';
import 'package:aquaroute/constants/brand_tokens.dart';
import 'package:aquaroute/constants/web_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('BrandSurfaces', () {
    // Most officers and owners are older readers; the light mode is held to
    // AAA for text, the dark mode to AA at least.
    test('light-mode text clears 7:1 on every surface', () {
      const s = BrandSurfaces.light;
      for (final bg in [s.paper, s.card, s.foam]) {
        expect(_contrast(s.ink, bg), greaterThan(7.0));
        expect(_contrast(s.inkMuted, bg), greaterThan(7.0), reason: 'muted text on $bg');
      }
    });

    test('dark-mode text clears 7:1 on every surface', () {
      const s = BrandSurfaces.dark;
      for (final bg in [s.paper, s.card, s.foam]) {
        expect(_contrast(s.ink, bg), greaterThan(7.0));
        expect(_contrast(s.inkMuted, bg), greaterThan(7.0), reason: 'muted text on $bg');
      }
    });

    test('the brand blue reads as text at 7:1, and carries 7:1 text as a button', () {
      for (final bg in [BrandSurfaces.light.paper, BrandSurfaces.light.card, BrandSurfaces.light.foam]) {
        expect(_contrast(BrandColors.harborBlue, bg), greaterThan(7.0), reason: 'blue on $bg');
      }
      for (final bg in [BrandSurfaces.dark.paper, BrandSurfaces.dark.card, BrandSurfaces.dark.foam]) {
        expect(_contrast(BrandColors.harborBlueOnDark, bg), greaterThan(7.0), reason: 'light blue on $bg');
      }
      expect(_contrast(Colors.white, BrandColors.harborBlue), greaterThan(7.0));
      expect(_contrast(BrandColors.onHarborBlueOnDark, BrandColors.harborBlueOnDark), greaterThan(7.0));
    });

    test('input outlines clear 3:1 so fields can be found', () {
      for (final s in [BrandSurfaces.light, BrandSurfaces.dark]) {
        expect(_contrast(s.inputBorder, s.card), greaterThan(3.0));
      }
    });
  });

  group('BrandStatus', () {
    test('status ink and gold labels read at 7:1 on every surface, both modes', () {
      for (final b in Brightness.values) {
        final s = BrandSurfaces.of(b);
        for (final ink in [
          BrandStatus.successFor(b),
          BrandStatus.warningFor(b),
          BrandStatus.dangerFor(b),
          BrandColors.sealGoldTextFor(b),
        ]) {
          for (final bg in [s.paper, s.card, s.foam]) {
            expect(_contrast(ink, bg), greaterThan(7.0), reason: '$ink on $bg, $b');
          }
        }
      }
    });
  });

  // The whole point of the tokens: the three products can't drift apart.
  test('app, website and admin share one set of surfaces', () {
    for (final pair in [
      (AppPalette.light, WebPalette.light, AdminPalette.light),
      (AppPalette.dark, WebPalette.dark, AdminPalette.dark),
    ]) {
      final (app, web, admin) = pair;
      expect(web.paper, app.paper);
      expect(admin.paper, app.paper);
      expect(web.ink, app.ink);
      expect(admin.inkMuted, app.inkMuted);
      expect(admin.card, web.card);
    }
  });
}
