import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../utils/csv_download.dart';
import 'portal/portal.dart';

/// The public site's address. Station pages live under `/stations/<id>`.
const publicSiteUrl = 'https://gentri-wasa.web.app';

String stationPublicLink(String stationId) => '$publicSiteUrl/stations/$stationId';

/// The station's own QR code and link, for a sign at the counter or a
/// sticker on a jug: customers scan it to see the station's accreditation
/// and record, and to order in the app.
class StationShareCard extends StatelessWidget {
  const StationShareCard({super.key, required this.stationId, required this.stationName});

  final String stationId;
  final String stationName;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: stationPublicLink(stationId)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
    }
  }

  Future<void> _download(BuildContext context) async {
    final painter = QrPainter(
      data: stationPublicLink(stationId),
      version: QrVersions.auto,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
    // Drawn onto white with a margin: a transparent PNG prints fine but
    // won't scan when shown on a dark screen.
    const size = 1024.0, margin = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
    canvas.translate(margin, margin);
    painter.paint(canvas, const Size(size - 2 * margin, size - 2 * margin));
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final safeName = stationName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase();
    final saved = downloadBytes('$safeName-qr.png', data.buffer.asUint8List(), 'image/png');
    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving the image works in the web portal. Here, use "Show large" and take a screenshot.')),
      );
    }
  }

  void _showLarge(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(stationName),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _qr(320),
              const SizedBox(height: 12),
              const Text('Scan to check this station with GenTri WASA', textAlign: TextAlign.center),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  /// Always black on white, whatever the theme: a QR code inverted for dark
  /// mode won't scan on many phones.
  Widget _qr(double size) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(12),
        child: QrImageView(
          data: stationPublicLink(stationId),
          size: size,
          backgroundColor: Colors.white,
          semanticsLabel: 'QR code linking to $stationName on the GenTri WASA website',
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PortalCard(
      lift: false,
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _qr(140),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your station\'s QR code', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Print it for your counter or jugs. Customers scan it to see your accreditation and record, '
                  'and to order in the app.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SelectableText(stationPublicLink(stationId), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(onPressed: () => _copy(context), icon: const Icon(Icons.copy), label: const Text('Copy link')),
                    OutlinedButton.icon(onPressed: () => _showLarge(context), icon: const Icon(Icons.zoom_in), label: const Text('Show large')),
                    if (kIsWeb)
                      OutlinedButton.icon(onPressed: () => _download(context), icon: const Icon(Icons.download), label: const Text('Save as image')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
