import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where map tiles come from, decided in one place for all nine maps.
///
/// With a MapTiler key present the app uses MapTiler; without one it uses
/// OpenStreetMap's own tile servers. OSM's tile policy permits app and
/// testing use provided the app identifies itself (the user agent below) and
/// shows attribution ([AppMapAttribution]) -- so the keyless path is a
/// legitimate testing configuration, not a workaround. MapTiler is the
/// production path once the client organisation owns an account: higher
/// limits, and none of OSM's caching obligations.
///
/// The key reaches the app the same way the Supabase keys do (main.dart):
/// `--dart-define` on web, where dotenv is unreliable in release builds, and
/// `.env` on mobile. Absent from both means OSM. A MapTiler key is visible to
/// the client by design, so restrict it to the app's origins in the MapTiler
/// dashboard rather than treating it as a secret.
class MapTileConfig {
  MapTileConfig._();

  static final String maptilerKey = _resolveKey();

  static bool get usesMapTiler => maptilerKey.isNotEmpty;

  static String _resolveKey() {
    const fromDefine = String.fromEnvironment('MAPTILER_KEY');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kIsWeb) return '';
    try {
      return dotenv.env['MAPTILER_KEY']?.trim() ?? '';
    } catch (_) {
      // dotenv isn't loaded (widget tests, or a build without .env) --
      // fall back to OSM rather than failing to draw a map at all.
      return '';
    }
  }

  static String get urlTemplate => usesMapTiler
      ? 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$maptilerKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}

/// The base map layer. Use this instead of a hand-written `TileLayer` so the
/// provider, user agent and zoom limits can never drift between screens --
/// they had been copy-pasted into nine files.
class AppMapTiles extends StatelessWidget {
  const AppMapTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: MapTileConfig.urlTemplate,
      // Identifies the app to the tile server. OSM blocks generic HTTP
      // library user agents outright.
      userAgentPackageName: 'ph.gentriwasa.aquaroute',
      maxNativeZoom: 19,
    );
  }
}

/// Map data attribution. Place it as the LAST child of a `FlutterMap` so
/// markers and routes never draw over it.
///
/// Required, not decorative: OpenStreetMap's licence and tile policy require
/// visible credit, and forbid hiding it behind a toggle -- which rules out
/// flutter_map's `RichAttributionWidget`, since that collapses into an info
/// button. None of the nine maps showed any attribution before this.
///
/// Set [showRoutingCredit] on maps that draw a computed route: the FOSSGIS
/// routing service additionally requires a link for reporting map errors.
class AppMapAttribution extends StatelessWidget {
  const AppMapAttribution({super.key, this.showRoutingCredit = false});

  final bool showRoutingCredit;

  static final _osmCopyright = Uri.parse('https://www.openstreetmap.org/copyright');
  static final _maptilerCopyright = Uri.parse('https://www.maptiler.com/copyright/');
  static final _fixTheMap = Uri.parse('https://www.openstreetmap.org/fixthemap');

  Widget _link(String label, String semanticsLabel, Uri target) {
    return TextButton(
      onPressed: () => launchUrl(target, mode: LaunchMode.externalApplication),
      // 48dp hit area (Touch_Target_Size) while the visible text stays the
      // small print attribution conventionally is.
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        foregroundColor: const Color(0xFF0B3D6B),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
      child: Text(label, semanticsLabel: semanticsLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        // Fixed light pill in both themes: it sits on map tiles, which are
        // light regardless of the app's theme.
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (MapTileConfig.usesMapTiler)
              _link('© MapTiler', 'MapTiler copyright', _maptilerCopyright),
            _link('© OpenStreetMap contributors', 'OpenStreetMap copyright and licence', _osmCopyright),
            if (showRoutingCredit) _link('Improve this map', 'Report a problem with the map', _fixTheMap),
          ],
        ),
      ),
    );
  }
}

/// A one-line status over a route map: the road distance and time when the
/// route is real, or a plain warning when it's the straight-line fallback.
///
/// The warning is the point. Straight lines between stops used to be drawn
/// with nothing to distinguish them from a real route, so a driver had no way
/// to know the line cut through buildings.
class RouteStatusBanner extends StatelessWidget {
  const RouteStatusBanner({
    super.key,
    required this.isApproximate,
    this.summary,
    this.onDark = false,
  });

  final bool isApproximate;

  /// e.g. "9.2 km · 15 min by road" (RoutePlan.summary).
  final String? summary;

  /// For the driver dashboard's dark, daylight-tuned palette.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final text = isApproximate
        ? 'Approximate route: straight lines between stops. Road directions are unavailable right now.'
        : summary;
    if (text == null) return const SizedBox.shrink();

    // Dark brown on cream for the warning (~7:1), and navy-on-white or
    // white-on-near-black for the summary -- all well past 4.5:1.
    final Color background;
    final Color foreground;
    if (isApproximate) {
      background = const Color(0xFFFFF4E5);
      foreground = const Color(0xFF7A4300);
    } else if (onDark) {
      background = const Color(0xFF161B22);
      foreground = Colors.white;
    } else {
      background = Colors.white;
      foreground = const Color(0xFF0B2545);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isApproximate ? Icons.warning_amber_rounded : Icons.route, color: foreground, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
