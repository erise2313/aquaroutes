import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone app on [number]. If that can't be done, says so and shows
/// the number -- the Call buttons used to fail silently when Android
/// reported no app for tel: links, which looked like a broken button.
Future<void> callPhone(BuildContext context, String number) async {
  final uri = Uri(scheme: 'tel', path: number);
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't open the phone app. The number is $number.")),
    );
  }
}
