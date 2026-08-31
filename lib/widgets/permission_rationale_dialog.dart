import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Shows a short rationale dialog explaining why the app wants location
/// access, but only right before the OS would actually prompt for it
/// (permission still `denied`, i.e. not yet decided) -- checking first
/// avoids nagging on every screen open once the user has already granted
/// or permanently denied the permission.
Future<void> maybeShowLocationRationale(BuildContext context, String message) async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.denied) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Location Access'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
}
