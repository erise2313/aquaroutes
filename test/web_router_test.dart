import 'package:flutter_test/flutter_test.dart';
import 'package:aquaroute/web_router.dart';
import 'package:aquaroute/widgets/web_nav_bar.dart';

void main() {
  group('WebRoutes', () {
    // Every WebPage that represents a real page must be reachable by URL,
    // or a nav/footer link silently falls back to an imperative push and
    // the address bar stops matching what is on screen.
    test('every WebPage has a path', () {
      for (final page in WebPage.values) {
        expect(WebRoutes.forPage[page], isNotNull, reason: 'no route for $page');
      }
    });

    test('paths are unique', () {
      final paths = WebRoutes.forPage.values.toList();
      expect(paths.toSet().length, paths.length, reason: 'two pages share a path');
    });

    test('every path is absolute and lower-case', () {
      for (final path in WebRoutes.forPage.values) {
        expect(path.startsWith('/'), isTrue, reason: '$path is not absolute');
        expect(path, path.toLowerCase(), reason: '$path is not lower-case');
      }
    });

    test('station detail nests under the directory', () {
      expect(WebRoutes.station('abc-123'), '/stations/abc-123');
      expect(WebRoutes.station('abc-123').startsWith(WebRoutes.stations), isTrue);
    });

    test('home is the root', () {
      expect(WebRoutes.forPage[WebPage.home], '/');
    });
  });

  group('buildWebRouter', () {
    test('resolves every declared page path without hitting the error page', () {
      final router = buildWebRouter();
      for (final entry in WebRoutes.forPage.entries) {
        final matches = router.configuration.findMatch(Uri.parse(entry.value));
        expect(matches.routes, isNotEmpty, reason: 'no route matched ${entry.value} (${entry.key})');
      }
    });

    test('resolves a station detail URL with its id', () {
      final router = buildWebRouter();
      final match = router.configuration.findMatch(Uri.parse('/stations/f0e1d2c3'));
      expect(match.routes, isNotEmpty);
      expect(match.pathParameters['id'], 'f0e1d2c3');
    });

    test('an unknown path matches nothing, so the error page handles it', () {
      final router = buildWebRouter();
      final match = router.configuration.findMatch(Uri.parse('/does-not-exist'));
      expect(match.routes, isEmpty);
    });
  });
}
